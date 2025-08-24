#!/bin/bash

# Quick Deployment Test Script
# Author: yungkolt
# Description: Test the hub-and-spoke network deployment in a safe way

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test configuration
TEST_RESOURCE_GROUP="rg-hub-spoke-test-$(date +%s)"
TEST_LOCATION="eastus"

print_status "Starting Hub-and-Spoke Network Test Deployment"
echo "=============================================="
echo "Test Resource Group: $TEST_RESOURCE_GROUP"
echo "Location: $TEST_LOCATION"
echo ""

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    exit 1
fi

if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
print_success "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Ask for confirmation
echo ""
print_warning "This will create Azure resources that may incur costs!"
print_status "Estimated cost: ~$40-50/day for full deployment"
print_status "Test will deploy: Hub network, 1 spoke, basic security (no Firewall/Bastion)"
echo ""

read -p "Do you want to proceed with the test deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Test deployment cancelled"
    exit 0
fi

# Start test deployment
print_status "Creating test resource group..."
az group create \
    --name $TEST_RESOURCE_GROUP \
    --location $TEST_LOCATION \
    --output none

print_success "Resource group created"

# Deploy minimal hub network
print_status "Deploying test hub network..."
az network vnet create \
    --resource-group $TEST_RESOURCE_GROUP \
    --name vnet-hub-test \
    --location $TEST_LOCATION \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name subnet-shared-services \
    --subnet-prefixes 10.0.3.0/24 \
    --output none

print_success "Hub network created"

# Deploy one test spoke
print_status "Deploying test spoke network..."
az network vnet create \
    --resource-group $TEST_RESOURCE_GROUP \
    --name vnet-prod-test \
    --location $TEST_LOCATION \
    --address-prefixes 10.1.0.0/16 \
    --subnet-name subnet-web-tier \
    --subnet-prefixes 10.1.1.0/24 \
    --output none

print_success "Spoke network created"

# Configure peering
print_status "Configuring network peering..."
az network vnet peering create \
    --resource-group $TEST_RESOURCE_GROUP \
    --name hub-to-prod \
    --vnet-name vnet-hub-test \
    --remote-vnet vnet-prod-test \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --output none

az network vnet peering create \
    --resource-group $TEST_RESOURCE_GROUP \
    --name prod-to-hub \
    --vnet-name vnet-prod-test \
    --remote-vnet vnet-hub-test \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --output none

print_success "Network peering configured"

# Create basic NSG
print_status "Creating basic Network Security Group..."
az network nsg create \
    --resource-group $TEST_RESOURCE_GROUP \
    --name nsg-test-web \
    --location $TEST_LOCATION \
    --output none

az network nsg rule create \
    --resource-group $TEST_RESOURCE_GROUP \
    --nsg-name nsg-test-web \
    --name allow-ssh \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --destination-port-ranges 22 \
    --output none

print_success "Network Security Group created"

# Associate NSG with subnet
print_status "Associating NSG with subnet..."
az network vnet subnet update \
    --resource-group $TEST_RESOURCE_GROUP \
    --vnet-name vnet-prod-test \
    --name subnet-web-tier \
    --network-security-group nsg-test-web \
    --output none

print_success "NSG associated with subnet"

# Create a small test VM
print_status "Creating test VM (this may take a few minutes)..."
az vm create \
    --resource-group $TEST_RESOURCE_GROUP \
    --name vm-test \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --vnet-name vnet-prod-test \
    --subnet subnet-web-tier \
    --public-ip-sku Standard \
    --admin-username azureuser \
    --generate-ssh-keys \
    --output none

print_success "Test VM created"

# Validate deployment
print_status "Validating deployment..."

# Check VNets
VNETS=$(az network vnet list --resource-group $TEST_RESOURCE_GROUP --query "length(@)")
print_status "Virtual networks created: $VNETS"

# Check peering
PEERING_STATUS=$(az network vnet peering show \
    --resource-group $TEST_RESOURCE_GROUP \
    --vnet-name vnet-hub-test \
    --name hub-to-prod \
    --query peeringState \
    --output tsv)
print_status "Peering status: $PEERING_STATUS"

if [ "$PEERING_STATUS" = "Connected" ]; then
    print_success "✓ Network peering is working"
else
    print_warning "⚠ Network peering may still be connecting"
fi

# Get VM details
VM_IP=$(az vm show \
    --resource-group $TEST_RESOURCE_GROUP \
    --name vm-test \
    --show-details \
    --query publicIps \
    --output tsv)

print_success "Test VM public IP: $VM_IP"

# Display summary
echo ""
print_status "Test Deployment Summary"
echo "======================="
echo "Resource Group: $TEST_RESOURCE_GROUP"
echo "Hub VNet: vnet-hub-test (10.0.0.0/16)"
echo "Spoke VNet: vnet-prod-test (10.1.0.0/16)"
echo "Test VM: vm-test ($VM_IP)"
echo ""

print_status "Resources created:"
az resource list --resource-group $TEST_RESOURCE_GROUP --output table

echo ""
print_success "Test deployment completed successfully!"
echo ""
print_status "Next steps:"
echo "1. SSH to test VM: ssh azureuser@$VM_IP"
echo "2. Test network connectivity from the VM"
echo "3. Review resources in Azure Portal"
echo "4. Clean up when done: az group delete --name $TEST_RESOURCE_GROUP --yes"
echo ""
print_warning "Remember to clean up resources to avoid ongoing charges!"

print_status "Test deployment script completed"
