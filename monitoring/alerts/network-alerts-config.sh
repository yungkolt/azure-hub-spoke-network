#!/bin/bash

# Network Monitoring Alerts Configuration
# Author: yungkolt
# Description: Configure monitoring alerts for hub-and-spoke network

RESOURCE_GROUP=$1
LAW_WORKSPACE_NAME=$2

if [ -z "$RESOURCE_GROUP" ] || [ -z "$LAW_WORKSPACE_NAME" ]; then
    echo "Usage: $0 <resource-group-name> <log-analytics-workspace-name>"
    exit 1
fi

echo "Configuring network monitoring alerts..."

# Get Log Analytics Workspace ID
LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LAW_WORKSPACE_NAME \
    --query id \
    --output tsv)

# Create action group for network alerts (if not exists)
az monitor action-group create \
    --resource-group $RESOURCE_GROUP \
    --name "network-security-alerts" \
    --short-name "netSecAlert" || true

ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group $RESOURCE_GROUP \
    --name "network-security-alerts" \
    --query id \
    --output tsv)

echo "Creating network security alerts..."

# Alert 1: High volume of denied connections
az monitor scheduled-query create \
    --resource-group $RESOURCE_GROUP \
    --name "HighDeniedConnections" \
    --description "Alert when there are many denied connections (potential attack)" \
    --severity 2 \
    --scopes $LAW_ID \
    --condition "count 'AzureNetworkAnalytics_CL | where TimeGenerated > ago(15m) | where SubType_s == \"FlowLog\" | where FlowStatus_s == \"D\" | summarize Count = count() | where Count > 100'" \
    --condition-query "AzureNetworkAnalytics_CL | where TimeGenerated > ago(15m) | where SubType_s == \"FlowLog\" | where FlowStatus_s == \"D\" | summarize Count = count()" \
    --condition-operator "GreaterThan" \
    --condition-threshold 100 \
    --condition-time-aggregation "Count" \
    --evaluation-frequency "PT5M" \
    --window-size "PT15M" \
    --actions $ACTION_GROUP_ID

# Alert 2: Firewall health degradation
az monitor scheduled-query create \
    --resource-group $RESOURCE_GROUP \
    --name "FirewallNoActivity" \
    --description "Alert when firewall shows no activity (potential issue)" \
    --severity 1 \
    --scopes $LAW_ID \
    --condition "count 'AzureDiagnostics | where TimeGenerated > ago(30m) | where Category in (\"AzureFirewallApplicationRule\", \"AzureFirewallNetworkRule\") | summarize Count = count() | where Count < 1'" \
    --condition-query "AzureDiagnostics | where TimeGenerated > ago(30m) | where Category in ('AzureFirewallApplicationRule', 'AzureFirewallNetworkRule') | summarize Count = count()" \
    --condition-operator "LessThan" \
    --condition-threshold 1 \
    --condition-time-aggregation "Count" \
    --evaluation-frequency "PT10M" \
    --window-size "PT30M" \
    --actions $ACTION_GROUP_ID

# Alert 3: Unusual outbound traffic volume
az monitor scheduled-query create \
    --resource-group $RESOURCE_GROUP \
    --name "HighOutboundTraffic" \
    --description "Alert on unusually high outbound traffic (potential data exfiltration)" \
    --severity 2 \
    --scopes $LAW_ID \
    --condition "count 'AzureNetworkAnalytics_CL | where TimeGenerated > ago(30m) | where SubType_s == \"FlowLog\" | summarize TotalOutbound = sum(OutboundBytes_d) | where TotalOutbound > 10000000000'" \
    --condition-query "AzureNetworkAnalytics_CL | where TimeGenerated > ago(30m) | where SubType_s == 'FlowLog' | summarize TotalOutbound = sum(OutboundBytes_d)" \
    --condition-operator "GreaterThan" \
    --condition-threshold 10000000000 \
    --condition-time-aggregation "Total" \
    --evaluation-frequency "PT15M" \
    --window-size "PT30M" \
    --actions $ACTION_GROUP_ID

# Alert 4: NSG blocked traffic spike
az monitor scheduled-query create \
    --resource-group $RESOURCE_GROUP \
    --name "NSGBlockedTrafficSpike" \
    --description "Alert on spike in NSG blocked traffic" \
    --severity 3 \
    --scopes $LAW_ID \
    --condition "count 'AzureDiagnostics | where TimeGenerated > ago(15m) | where Category == \"NetworkSecurityGroupEvent\" | where type_s == \"block\" | summarize Count = count() | where Count > 50'" \
    --condition-query "AzureDiagnostics | where TimeGenerated > ago(15m) | where Category == 'NetworkSecurityGroupEvent' | where type_s == 'block' | summarize Count = count()" \
    --condition-operator "GreaterThan" \
    --condition-threshold 50 \
    --condition-time-aggregation "Count" \
    --evaluation-frequency "PT5M" \
    --window-size "PT15M" \
    --actions $ACTION_GROUP_ID

echo "Network monitoring alerts configured successfully!"
echo "Configured alerts:"
echo "- High Denied Connections (Severity 2)"
echo "- Firewall No Activity (Severity 1)" 
echo "- High Outbound Traffic (Severity 2)"
echo "- NSG Blocked Traffic Spike (Severity 3)"
