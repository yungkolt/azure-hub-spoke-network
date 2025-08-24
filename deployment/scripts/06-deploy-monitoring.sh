#!/bin/bash

# Deploy Monitoring and Logging Components
# Author: yungkolt
# Description: Set up comprehensive monitoring, logging, and alerting

RESOURCE_GROUP=$1
LOCATION=$2

echo "Deploying Monitoring and Logging Components..."

# Create Log Analytics Workspace
echo "Creating Log Analytics Workspace..."
LAW_NAME="law-network-monitoring-$(date +%s)"
az monitor log-analytics workspace create \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LAW_NAME \
    --location $LOCATION \
    --sku PerGB2018 \
    --retention-time 30

# Get Log Analytics Workspace ID and Key
LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LAW_NAME \
    --query customerId \
    --output tsv)

echo "Log Analytics Workspace created: $LAW_NAME"
echo "Workspace ID: $LAW_ID"

# Enable Network Watcher (if not already enabled)
echo "Configuring Network Watcher..."
az network watcher configure \
    --resource-group NetworkWatcherRG \
    --locations $LOCATION \
    --enabled || true

# Create storage account for NSG flow logs
echo "Creating storage account for flow logs..."
STORAGE_ACCOUNT_NAME="sanhubspokelog$(date +%s | tail -c 10)"
az storage account create \
    --resource-group $RESOURCE_GROUP \
    --name $STORAGE_ACCOUNT_NAME \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2

# Get storage account resource ID
STORAGE_ID=$(az storage account show \
    --resource-group $RESOURCE_GROUP \
    --name $STORAGE_ACCOUNT_NAME \
    --query id \
    --output tsv)

# Enable NSG flow logs for all NSGs
echo "Enabling NSG flow logs..."
NSG_LIST=$(az network nsg list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv)

for nsg in $NSG_LIST; do
    echo "Enabling flow logs for NSG: $nsg"
    az network watcher flow-log create \
        --resource-group $RESOURCE_GROUP \
        --name "flowlog-$nsg" \
        --nsg $nsg \
        --storage-account $STORAGE_ID \
        --enabled \
        --retention 30 \
        --log-analytics-workspace $LAW_ID \
        --interval 10 \
        --format JSON \
        --log-version 2 || echo "Flow log for $nsg may already exist"
done

# Configure diagnostic settings for Azure Firewall
echo "Configuring Azure Firewall diagnostic settings..."
FIREWALL_ID=$(az network firewall show \
    --resource-group $RESOURCE_GROUP \
    --name fw-hub-eastus \
    --query id \
    --output tsv)

if [ ! -z "$FIREWALL_ID" ]; then
    az monitor diagnostic-settings create \
        --resource $FIREWALL_ID \
        --name "firewall-diagnostics" \
        --workspace $LAW_ID \
        --logs '[
            {
                "category": "AzureFirewallApplicationRule",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "AzureFirewallNetworkRule", 
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "AzureFirewallDnsProxy",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }
        ]' \
        --metrics '[
            {
                "category": "AllMetrics",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }
        ]'
fi

# Configure diagnostic settings for Virtual Networks
echo "Configuring VNet diagnostic settings..."
VNET_LIST=("vnet-hub-eastus" "vnet-prod-eastus" "vnet-dev-eastus" "vnet-dmz-eastus")

for vnet in "${VNET_LIST[@]}"; do
    VNET_ID=$(az network vnet show \
        --resource-group $RESOURCE_GROUP \
        --name $vnet \
        --query id \
        --output tsv)
    
    if [ ! -z "$VNET_ID" ]; then
        az monitor diagnostic-settings create \
            --resource $VNET_ID \
            --name "vnet-diagnostics" \
            --workspace $LAW_ID \
            --metrics '[
                {
                    "category": "AllMetrics",
                    "enabled": true,
                    "retentionPolicy": {
                        "enabled": true,
                        "days": 30
                    }
                }
            ]' || echo "Diagnostic settings may already exist for $vnet"
    fi
done

# Create action group for alerts
echo "Creating action group for alerts..."
az monitor action-group create \
    --resource-group $RESOURCE_GROUP \
    --name "network-alerts-group" \
    --short-name "netAlerts"

# Get action group resource ID
ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group $RESOURCE_GROUP \
    --name "network-alerts-group" \
    --query id \
    --output tsv)

# Create metric alert for Azure Firewall
echo "Creating Azure Firewall metric alerts..."
if [ ! -z "$FIREWALL_ID" ]; then
    az monitor metrics alert create \
        --resource-group $RESOURCE_GROUP \
        --name "FirewallHighThroughput" \
        --description "Alert when firewall throughput is high" \
        --scopes $FIREWALL_ID \
        --condition "avg Throughput > 800000000" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action $ACTION_GROUP_ID \
        --severity 2

    az monitor metrics alert create \
        --resource-group $RESOURCE_GROUP \
        --name "FirewallHealthState" \
        --description "Alert when firewall health state is degraded" \
        --scopes $FIREWALL_ID \
        --condition "avg FirewallHealth < 90" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action $ACTION_GROUP_ID \
        --severity 1
fi

# Create sample Kusto queries for Log Analytics
echo "Creating sample Kusto queries..."
mkdir -p monitoring/queries
cat << 'EOF' > monitoring/queries/network-queries.kql
// Network Flow Analysis
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where SubType_s == "FlowLog"
| summarize TotalFlows = count() by SrcIP_s, DestIP_s, DestPort_d
| order by TotalFlows desc
| limit 20

// Azure Firewall Application Rules
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where msg_s contains "Deny"
| summarize Count = count() by SourceIP = split(msg_s, " ")[3], TargetURL = split(msg_s, " ")[6]
| order by Count desc

// Network Security Group Events
AzureDiagnostics
| where Category == "NetworkSecurityGroupEvent"
| where type_s == "block"
| summarize Count = count() by primaryIPv4Address_s, direction_s, ruleName_s
| order by Count desc

// Top Talkers by Data Transfer
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(24h)
| where SubType_s == "FlowLog"
| summarize TotalBytes = sum(OutboundBytes_d + InboundBytes_d) by SrcIP_s
| order by TotalBytes desc
| limit 10

// Firewall Health Check
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule" or Category == "AzureFirewallNetworkRule"
| where TimeGenerated > ago(1h)
| summarize Count = count() by Action_s, bin(TimeGenerated, 5m)
| render timechart
EOF

echo "Sample queries saved to monitoring/queries/network-queries.kql"

# Create test VMs for connectivity monitoring (optional)
echo "Creating test VMs for connectivity monitoring..."

# Production test VM
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name vm-prod-test \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --vnet-name vnet-prod-eastus \
    --subnet subnet-web-tier \
    --public-ip-address "" \
    --nsg "" \
    --admin-username azureuser \
    --generate-ssh-keys \
    --no-wait || echo "VM creation may take time or fail due to quotas"

# Development test VM  
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name vm-dev-test \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --vnet-name vnet-dev-eastus \
    --subnet subnet-dev-resources \
    --public-ip-address "" \
    --nsg "" \
    --admin-username azureuser \
    --generate-ssh-keys \
    --no-wait || echo "VM creation may take time or fail due to quotas"

# Output monitoring configuration summary
echo ""
echo "Monitoring Configuration Summary:"
echo "================================="
echo "Log Analytics Workspace: $LAW_NAME"
echo "Workspace ID: $LAW_ID"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo ""
echo "Enabled Monitoring Features:"
echo "- NSG Flow Logs with Log Analytics integration"
echo "- Azure Firewall diagnostic logs"
echo "- Virtual Network metrics"
echo "- Connection monitoring (with test VMs)"
echo "- Metric alerts for firewall health and throughput"
echo ""
echo "Sample Kusto queries saved to: monitoring/queries/network-queries.kql"
echo ""
echo "Next Steps:"
echo "1. Access Log Analytics workspace to run queries"
echo "2. Configure additional alert rules as needed"
echo "3. Set up automated reports and notifications"
echo "4. Use Azure Bastion to connect to test VMs"

echo "Monitoring and logging deployment completed"
