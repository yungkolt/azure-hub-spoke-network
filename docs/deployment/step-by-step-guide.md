# Azure Hub-and-Spoke Network - Step-by-Step Deployment Guide

## Overview

This guide provides detailed instructions for deploying the Azure hub-and-spoke network architecture. The deployment creates a secure, scalable network infrastructure following Microsoft's recommended patterns.

## Prerequisites

### Required Tools
- **Azure CLI** version 2.30.0 or later
- **Git** for repository management
- **Bash shell** (Linux/macOS/WSL on Windows)
- **Text editor** for configuration files

### Azure Requirements
- Azure subscription with **Contributor** access
- Sufficient quotas for:
  - Virtual Networks: 4+
  - Public IP addresses: 3+
  - Network Security Groups: 5+
  - Azure Firewall: 1
  - Azure Bastion: 1

### Installation Commands

```bash
# Install Azure CLI (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Azure CLI (macOS)
brew install azure-cli

# Verify installation
az --version
```

## Quick Start Deployment

### Step 1: Clone and Prepare Repository
```bash
# Clone the repository
git clone https://github.com/yungkolt/azure-hub-spoke-network.git
cd azure-hub-spoke-network

# Make scripts executable
chmod +x deployment/scripts/*.sh
chmod +x testing/*.sh
```

### Step 2: Login to Azure
```bash
# Login to Azure
az login

# List subscriptions
az account list --output table

# Set subscription (if you have multiple)
az account set --subscription "Your-Subscription-Name-or-ID"

# Verify current subscription
az account show
```

### Step 3: Run Automated Deployment
```bash
# Navigate to scripts directory
cd deployment/scripts

# Run the main deployment script
./deploy.sh
```

The deployment will:
1. ✅ Check prerequisites and permissions
2. ✅ Create resource group
3. ✅ Deploy hub network infrastructure
4. ✅ Deploy spoke networks (Production, Development, DMZ)
5. ✅ Configure network peering
6. ✅ Deploy security components (Firewall, NSGs, Bastion)
7. ✅ Set up routing tables
8. ✅ Configure monitoring and logging
9. ✅ Validate deployment

**Expected completion time: 30-45 minutes**

## Manual Step-by-Step Deployment

If you prefer more control over each phase:

### Phase 1: Hub Network Infrastructure
```bash
./01-deploy-hub.sh rg-hub-spoke-network eastus
```

**What this deploys:**
- Hub virtual network (10.0.0.0/16)
- Gateway subnet for VPN/ExpressRoute
- Azure Firewall subnet
- Azure Bastion subnet
- Shared services subnet

### Phase 2: Spoke Networks
```bash
./02-deploy-spokes.sh rg-hub-spoke-network eastus
```

**What this deploys:**
- **Production spoke** (10.1.0.0/16): Web, app, and data tiers
- **Development spoke** (10.2.0.0/16): Development and testing resources
- **DMZ spoke** (10.3.0.0/16): Public-facing services

### Phase 3: Network Connectivity
```bash
./03-configure-peering.sh rg-hub-spoke-network
```

**What this configures:**
- Hub-to-spoke peering connections
- Spoke-to-hub peering connections
- Gateway transit configuration
- Forwarded traffic allowance

### Phase 4: Security Implementation
```bash
./04-deploy-security.sh rg-hub-spoke-network eastus
```

**What this deploys:**
- Network Security Groups with micro-segmentation rules
- Azure Firewall with basic policies
- Azure Bastion for secure VM access
- Public IP addresses for internet connectivity

### Phase 5: Traffic Routing
```bash
./05-configure-routing.sh rg-hub-spoke-network
```

**What this configures:**
- Custom route tables
- Routes to direct traffic through firewall
- Spoke-to-spoke communication routing
- Internet egress routing

### Phase 6: Monitoring Setup
```bash
./06-deploy-monitoring.sh rg-hub-spoke-network eastus
```

**What this deploys:**
- Log Analytics workspace
- NSG Flow Logs with analytics integration
- Azure Firewall diagnostic logs
- Storage account for log retention
- Basic alerting rules
- Test VMs for connectivity validation

## Post-Deployment Configuration

### 1. Verify Deployment Success
```bash
# Run connectivity tests
cd ../../testing
./connectivity-tests.sh rg-hub-spoke-network
```

### 2. Access Azure Portal
Navigate to [Azure Portal](https://portal.azure.com) and verify:
- All virtual networks are created
- Peering connections show "Connected" status
- Azure Firewall shows "Succeeded" provisioning state
- Azure Bastion is ready

### 3. Test Network Connectivity

#### Using Azure Bastion
1. Go to **Virtual machines** in Azure Portal
2. Select any test VM
3. Click **Connect** → **Bastion**
4. Enter username and SSH key/password
5. Test connectivity to other subnets

#### Network Testing Commands
```bash
# From a VM, test connectivity
ping 10.0.3.4    # Hub shared services
ping 10.1.1.4    # Production web tier
ping 10.2.1.4    # Development resources

# Test internet connectivity (should go through firewall)
curl -I https://www.microsoft.com
nslookup www.google.com
```

### 4. Configure Firewall Rules

#### Add Application Rules
```bash
# Allow specific websites
az network firewall policy rule-collection-group collection add-filter-collection \
  --resource-group rg-hub-spoke-network \
  --policy-name fw-policy-hub \
  --rule-collection-group-name DefaultApplicationRuleCollectionGroup \
  --name AllowMicrosoft \
  --collection-priority 200 \
  --action Allow \
  --rule-name AllowMicrosoftSites \
  --rule-type ApplicationRule \
  --protocols Https=443 Http=80 \
  --source-addresses 10.1.0.0/16 10.2.0.0/16 \
  --target-fqdns "*.microsoft.com" "*.azure.com" "*.ubuntu.com"
```

#### Add Network Rules
```bash
# Allow DNS traffic
az network firewall policy rule-collection-group collection add-filter-collection \
  --resource-group rg-hub-spoke-network \
  --policy-name fw-policy-hub \
  --rule-collection-group-name DefaultNetworkRuleCollectionGroup \
  --name AllowDNS \
  --collection-priority 100 \
  --action Allow \
  --rule-name AllowDNSTraffic \
  --rule-type NetworkRule \
  --protocols UDP \
  --source-addresses 10.1.0.0/16 10.2.0.0/16 10.3.0.0/16 \
  --destination-addresses "168.63.129.16" "8.8.8.8" \
  --destination-ports 53
```

### 5. Set Up Monitoring and Alerting

#### Access Log Analytics Workspace
1. Go to **Log Analytics workspaces** in Azure Portal
2. Open the created workspace (law-network-monitoring-*)
3. Navigate to **Logs** section
4. Run sample queries:

```kql
// View recent firewall activity
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s
| limit 50

// Analyze network flows
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| where TimeGenerated > ago(1h)
| summarize count() by SrcIP_s, DestIP_s
| order by count_ desc
```

#### Configure Custom Alerts
```bash
# Create alert for high firewall traffic
az monitor metrics alert create \
  --resource-group rg-hub-spoke-network \
  --name "HighFirewallTraffic" \
  --description "Alert when firewall processes high traffic volume" \
  --condition "avg Throughput > 500000000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2
```

## Validation and Testing

### Network Connectivity Tests

#### 1. Verify Hub-Spoke Connectivity
```bash
# Check peering status
az network vnet peering list \
  --resource-group rg-hub-spoke-network \
  --vnet-name vnet-hub-eastus \
  --output table
```

#### 2. Test Security Segmentation
```bash
# Verify NSG rules are working
az network nsg rule list \
  --resource-group rg-hub-spoke-network \
  --nsg-name nsg-web-tier \
  --include-default \
  --output table
```

#### 3. Validate Routing Configuration
```bash
# Check effective routes
az network nic show-effective-route-table \
  --resource-group rg-hub-spoke-network \
  --name vm-prod-testVMNic
```

### Security Validation

#### 1. Test Firewall Rules
```bash
# From a VM, test blocked websites
curl -I https://blocked-site.com  # Should be blocked

# Test allowed traffic
curl -I https://www.microsoft.com  # Should work
```

#### 2. Verify Bastion Access
- Connect to VMs only through Bastion
- Verify direct SSH/RDP is blocked
- Test connectivity between different tiers

#### 3. Check NSG Flow Logs
```bash
# Query NSG flow logs
az monitor log-analytics query \
  --workspace law-network-monitoring-* \
  --analytics-query "AzureNetworkAnalytics_CL | where SubType_s == 'FlowLog' | limit 10"
```

## Customization Options

### Scaling the Architecture

#### Add New Spoke Network
```bash
# Create new spoke (e.g., staging environment)
az network vnet create \
  --resource-group rg-hub-spoke-network \
  --name vnet-staging-eastus \
  --address-prefixes 10.4.0.0/16 \
  --subnet-name subnet-staging-apps \
  --subnet-prefixes 10.4.1.0/24

# Configure peering
az network vnet peering create \
  --resource-group rg-hub-spoke-network \
  --name hub-to-staging \
  --vnet-name vnet-hub-eastus \
  --remote-vnet vnet-staging-eastus \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --allow-gateway-transit
```

#### Add VPN Gateway for Hybrid Connectivity
```bash
# Create VPN Gateway subnet (if not exists)
az network vnet subnet create \
  --resource-group rg-hub-spoke-network \
  --vnet-name vnet-hub-eastus \
  --name GatewaySubnet \
  --address-prefixes 10.0.0.0/27

# Create VPN Gateway
az network vnet-gateway create \
  --resource-group rg-hub-spoke-network \
  --name vpn-gateway-hub \
  --vnet vnet-hub-eastus \
  --public-ip-addresses pip-vpn-gateway \
  --gateway-type Vpn \
  --sku VpnGw1 \
  --vpn-type RouteBased
```

### Environment-Specific Configurations

#### Production Environment
- Enable DDoS Protection Standard
- Use Azure Firewall Premium
- Implement Azure Sentinel
- Add ExpressRoute connectivity

#### Development Environment
- Use Azure Firewall Basic
- Relaxed NSG rules for testing
- Shorter log retention periods
- Automated shutdown schedules

### Multi-Region Deployment

#### Deploy in Secondary Region
```bash
# Deploy to West US 2
LOCATION="westus2"
RESOURCE_GROUP="rg-hub-spoke-network-westus2"

# Run deployment with different parameters
./deploy.sh
```

#### Configure Global Peering
```bash
# Peer hub networks across regions
az network vnet peering create \
  --resource-group rg-hub-spoke-network \
  --name hub-eastus-to-westus2 \
  --vnet-name vnet-hub-eastus \
  --remote-vnet /subscriptions/[SUBSCRIPTION]/resourceGroups/rg-hub-spoke-network-westus2/providers/Microsoft.Network/virtualNetworks/vnet-hub-westus2 \
  --allow-vnet-access \
  --allow-forwarded-traffic
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Deployment Failures

**Issue**: Resource group creation fails
```bash
# Solution: Check permissions and subscription
az account show
az role assignment list --assignee $(az account show --query user.name --output tsv)
```

**Issue**: Firewall deployment timeout
```bash
# Solution: Check firewall status and wait
az network firewall show \
  --resource-group rg-hub-spoke-network \
  --name fw-hub-eastus \
  --query provisioningState
```

#### 2. Connectivity Issues

**Issue**: VMs cannot reach internet
```bash
# Check routing configuration
az network route-table show \
  --resource-group rg-hub-spoke-network \
  --name rt-spoke-to-firewall

# Verify firewall rules
az network firewall policy rule-collection-group list \
  --resource-group rg-hub-spoke-network \
  --policy-name fw-policy-hub
```

**Issue**: Spoke-to-spoke communication fails
```bash
# Check peering status
az network vnet peering show \
  --resource-group rg-hub-spoke-network \
  --vnet-name vnet-hub-eastus \
  --name hub-to-prod

# Verify NSG rules allow traffic
az network nsg rule list \
  --resource-group rg-hub-spoke-network \
  --nsg-name nsg-web-tier
```

#### 3. Bastion Connection Issues

**Issue**: Cannot connect via Bastion
```bash
# Check Bastion status
az network bastion show \
  --resource-group rg-hub-spoke-network \
  --name bastion-hub

# Verify VM is running
az vm show \
  --resource-group rg-hub-spoke-network \
  --name vm-prod-test \
  --show-details
```

#### 4. Monitoring Issues

**Issue**: Flow logs not appearing
```bash
# Check flow log configuration
az network watcher flow-log list \
  --resource-group rg-hub-spoke-network

# Verify storage account access
az storage account show \
  --resource-group rg-hub-spoke-network \
  --name [storage-account-name]
```

### Debug Commands

```bash
# View all resources in resource group
az resource list --resource-group rg-hub-spoke-network --output table

# Check deployment operations
az deployment group list --resource-group rg-hub-spoke-network

# View activity log for errors
az monitor activity-log list --resource-group rg-hub-spoke-network --max-events 50

# Test network connectivity
az network watcher test-connectivity \
  --source-resource vm-prod-test \
  --dest-address 10.2.1.4 \
  --dest-port 22 \
  --resource-group rg-hub-spoke-network
```

## Cost Management

### Daily Cost Estimates (USD)
- **Azure Firewall Standard**: ~$30/day
- **Azure Bastion Standard**: ~$5/day
- **VPN Gateway Basic**: ~$1/day (if deployed)
- **Log Analytics**: ~$2-5/day (depends on data volume)
- **Storage Account**: ~$0.50/day
- **Virtual Networks**: ~$0.10/day
- **Public IP addresses**: ~$0.12/day each
- **Test VMs**: ~$2-5/day each (Standard_B1s)

### Cost Optimization Tips

#### 1. Use Scheduled Shutdown for Test VMs
```bash
# Set auto-shutdown for development VMs
az vm auto-shutdown \
  --resource-group rg-hub-spoke-network \
  --name vm-dev-test \
  --time 1800 \
  --timezone "UTC"
```

#### 2. Optimize Log Retention
```bash
# Reduce log retention for cost savings
az monitor log-analytics workspace update \
  --resource-group rg-hub-spoke-network \
  --workspace-name law-network-monitoring-* \
  --retention-time 7
```

#### 3. Use Azure Firewall Basic for Non-Production
```bash
# Deploy Basic SKU for development environments
az network firewall create \
  --resource-group rg-hub-spoke-network \
  --name fw-hub-eastus \
  --sku AZFW_VNet \
  --tier Basic
```

## Cleanup and Resource Management

### Selective Cleanup (Keep Network, Remove Expensive Resources)
```bash
./cleanup.sh --selective
```

### Complete Cleanup (Delete Everything)
```bash
./cleanup.sh --complete
```

### Check Cleanup Status
```bash
./cleanup.sh --status
```

## Next Steps

### 1. Security Enhancements
- Enable Azure Security Center recommendations
- Implement Azure Sentinel for SIEM
- Add DDoS Protection Standard
- Deploy Web Application Firewall

### 2. Operational Improvements
- Set up automated backups
- Implement Infrastructure as Code with Terraform
- Add CI/CD pipelines for network changes
- Create runbooks for common operations

### 3. Scaling Considerations
- Plan for additional spokes
- Consider Azure Virtual WAN for global connectivity
- Implement Azure Private DNS zones
- Add load balancers for high availability

### 4. Compliance and Governance
- Implement Azure Policy for governance
- Set up compliance monitoring
- Add resource tagging strategy
- Implement cost management alerts

---

**Need Help?**
- Check the [troubleshooting section](#troubleshooting)
- Review Azure documentation for specific services
- Create GitHub issues for repository-specific problems
- Use Azure support for production issues
