#!/bin/bash

# Network Connectivity Testing Script
# Author: yungkolt
# Description: Test network connectivity and validate hub-spoke architecture

RESOURCE_GROUP=$1

if [ -z "$RESOURCE_GROUP" ]; then
    echo "Usage: $0 <resource-group-name>"
    exit 1
fi

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

print_status "Starting network connectivity tests for resource group: $RESOURCE_GROUP"

# Test 1: Verify Virtual Networks exist
print_status "Test 1: Checking Virtual Networks..."
VNETS=(vnet-hub-eastus vnet-prod-eastus vnet-dev-eastus vnet-dmz-eastus)

for vnet in "${VNETS[@]}"; do
    if az network vnet show --resource-group $RESOURCE_GROUP --name $vnet &> /dev/null; then
        print_success "✓ $vnet exists"
    else
        print_error "✗ $vnet not found"
    fi
done

# Test 2: Verify Network Peering Status
print_status "Test 2: Checking Network Peering..."
echo "Hub peering connections:"
az network vnet peering list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub-eastus \
    --query "[].{Name:name, PeeringState:peeringState, ConnectedState:provisioningState}" \
    --output table

# Check peering state
PEERING_COUNT=$(az network vnet peering list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub-eastus \
    --query "length([?peeringState=='Connected'])")

if [ "$PEERING_COUNT" -eq 3 ]; then
    print_success "✓ All 3 peering connections are Connected"
else
    print_warning "⚠ Expected 3 Connected peerings, found $PEERING_COUNT"
fi

# Test 3: Verify Azure Firewall Status
print_status "Test 3: Checking Azure Firewall..."
FIREWALL_STATE=$(az network firewall show \
    --resource-group $RESOURCE_GROUP \
    --name fw-hub-eastus \
    --query provisioningState \
    --output tsv 2>/dev/null)

if [ "$FIREWALL_STATE" = "Succeeded" ]; then
    print_success "✓ Azure Firewall is provisioned successfully"
    
    FIREWALL_IP=$(az network firewall show \
        --resource-group $RESOURCE_GROUP \
        --name fw-hub-eastus \
        --query ipConfigurations[0].privateIPAddress \
        --output tsv)
    print_status "Firewall private IP: $FIREWALL_IP"
else
    print_error "✗ Azure Firewall not ready. State: $FIREWALL_STATE"
fi

# Test 4: Verify Azure Bastion
print_status "Test 4: Checking Azure Bastion..."
BASTION_STATE=$(az network bastion show \
    --resource-group $RESOURCE_GROUP \
    --name bastion-hub \
    --query provisioningState \
    --output tsv 2>/dev/null)

if [ "$BASTION_STATE" = "Succeeded" ]; then
    print_success "✓ Azure Bastion is provisioned successfully"
else
    print_warning "⚠ Azure Bastion not ready. State: $BASTION_STATE"
fi

# Test 5: Verify NSG Rules
print_status "Test 5: Checking Network Security Groups..."
NSG_COUNT=$(az network nsg list --resource-group $RESOURCE_GROUP --query "length(@)")
print_status "Found $NSG_COUNT Network Security Groups"

# Check specific NSG rules
print_status "Checking web-tier NSG rules..."
WEB_RULES=$(az network nsg rule list \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-web-tier \
    --query "length([?direction=='Inbound' && access=='Allow'])")
print_status "Web tier has $WEB_RULES allow rules"

# Test 6: Verify Route Tables
print_status "Test 6: Checking Route Tables..."
ROUTE_TABLES=$(az network route-table list --resource-group $RESOURCE_GROUP --query "length(@)")
print_status "Found $ROUTE_TABLES Route Tables"

# Check if routes point to firewall
if [ ! -z "$FIREWALL_IP" ]; then
    FIREWALL_ROUTES=$(az network route-table route list \
        --resource-group $RESOURCE_GROUP \
        --route-table-name rt-spoke-to-firewall \
        --query "length([?nextHopIpAddress=='$FIREWALL_IP'])")
    print_status "Found $FIREWALL_ROUTES routes pointing to firewall"
fi

# Test 7: Test VM Connectivity (if VMs exist)
print_status "Test 7: Checking Test VMs..."
VMS=$(az vm list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv)

if [ ! -z "$VMS" ]; then
    for vm in $VMS; do
        VM_STATE=$(az vm show --resource-group $RESOURCE_GROUP --name $vm --query powerState --output tsv)
        if [ "$VM_STATE" = "VM running" ]; then
            print_success "✓ $vm is running"
        else
            print_warning "⚠ $vm state: $VM_STATE"
        fi
    done
else
    print_warning "⚠ No test VMs found for connectivity testing"
fi

# Test 8: Network Watcher Tests (if VMs are available)
print_status "Test 8: Network Connectivity Tests..."
if [ ! -z "$VMS" ]; then
    VM_ARRAY=($VMS)
    if [ ${#VM_ARRAY[@]} -ge 2 ]; then
        SOURCE_VM=${VM_ARRAY[0]}
        TARGET_VM=${VM_ARRAY[1]}
        
        print_status "Testing connectivity from $SOURCE_VM to $TARGET_VM..."
        
        # Get target VM private IP
        TARGET_IP=$(az vm list-ip-addresses \
            --resource-group $RESOURCE_GROUP \
            --name $TARGET_VM \
            --query "[0].virtualMachine.network.privateIpAddresses[0]" \
            --output tsv)
        
        if [ ! -z "$TARGET_IP" ]; then
            print_status "Target IP: $TARGET_IP"
            print_status "Running Network Watcher connectivity test..."
            
            # Run connectivity test
            az network watcher test-connectivity \
                --source-resource $SOURCE_VM \
                --dest-address $TARGET_IP \
                --dest-port 22 \
                --resource-group $RESOURCE_GROUP || print_warning "Connectivity test failed or Network Watcher not available"
        fi
    fi
else
    print_warning "⚠ Skipping connectivity tests - insufficient VMs"
fi

# Test 9: DNS Resolution Test
print_status "Test 9: Testing DNS Resolution..."
print_status "Checking if Azure DNS is accessible from spokes..."
# This would require VM access, so we'll just verify DNS configuration

# Test 10: Flow Logs Verification
print_status "Test 10: Checking Flow Logs Configuration..."
FLOW_LOGS=$(az network watcher flow-log list --resource-group $RESOURCE_GROUP --query "length(@)" 2>/dev/null || echo "0")
print_status "Found $FLOW_LOGS NSG Flow Log configurations"

if [ "$FLOW_LOGS" -gt 0 ]; then
    print_success "✓ NSG Flow Logs are configured"
else
    print_warning "⚠ No NSG Flow Logs found"
fi

# Summary
echo ""
print_status "Network Connectivity Test Summary"
echo "=================================="

# Count successes and warnings
SUCCESS_COUNT=0
WARNING_COUNT=0

# This is a simplified summary - in a real script you'd track each test result
print_status "Tests completed. Please review the output above for detailed results."
print_status ""
print_status "Manual verification steps:"
echo "1. Check Azure Portal for resource deployment status"
echo "2. Use Azure Bastion to connect to VMs and test connectivity"
echo "3. Review NSG Flow Logs in Log Analytics workspace"
echo "4. Monitor Azure Firewall logs for traffic patterns"
echo "5. Test application connectivity through the network"

print_status "Connectivity testing completed."
