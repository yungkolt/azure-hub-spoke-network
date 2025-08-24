#!/bin/bash

# Cleanup Azure Hub-and-Spoke Network Resources
# Author: yungkolt
# Description: Safe cleanup of all deployed resources with confirmation prompts

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="rg-hub-spoke-network"

# Function to print colored output
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

# Function to check if resource group exists
check_resource_group() {
    if ! az group show --name $RESOURCE_GROUP &> /dev/null; then
        print_error "Resource group '$RESOURCE_GROUP' does not exist."
        exit 1
    fi
}

# Function to list all resources in the resource group
list_resources() {
    print_status "Resources to be deleted:"
    echo "========================="
    az resource list --resource-group $RESOURCE_GROUP --output table
    echo ""
}

# Function to get resource count
get_resource_count() {
    az resource list --resource-group $RESOURCE_GROUP --query "length(@)"
}

# Function to estimate costs of remaining resources
estimate_costs() {
    print_status "Estimating daily costs of current resources..."
    
    # Check for expensive resources
    FIREWALL_COUNT=$(az network firewall list --resource-group $RESOURCE_GROUP --query "length(@)" 2>/dev/null || echo "0")
    BASTION_COUNT=$(az network bastion list --resource-group $RESOURCE_GROUP --query "length(@)" 2>/dev/null || echo "0")
    VPN_GW_COUNT=$(az network vnet-gateway list --resource-group $RESOURCE_GROUP --query "length(@)" 2>/dev/null || echo "0")
    VM_COUNT=$(az vm list --resource-group $RESOURCE_GROUP --query "length(@)" 2>/dev/null || echo "0")
    
    echo ""
    echo "Estimated Daily Costs (USD):"
    echo "============================"
    echo "Azure Firewalls: $FIREWALL_COUNT x ~\$30/day = ~\$$(($FIREWALL_COUNT * 30))/day"
    echo "Azure Bastion: $BASTION_COUNT x ~\$5/day = ~\$$(($BASTION_COUNT * 5))/day"  
    echo "VPN Gateways: $VPN_GW_COUNT x ~\$1/day = ~\$$(($VPN_GW_COUNT * 1))/day"
    echo "VMs: $VM_COUNT x varies by size (est. \$2-10/day each)"
    echo "VNets, NSGs, Public IPs: minimal cost (~\$0.50/day total)"
    echo ""
}

# Function to cleanup individual resource types (selective cleanup)
cleanup_expensive_resources() {
    print_status "Performing selective cleanup of expensive resources..."
    
    # Stop and deallocate VMs first
    print_status "Stopping VMs..."
    VM_LIST=$(az vm list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv)
    
    if [ ! -z "$VM_LIST" ]; then
        for vm in $VM_LIST; do
            print_status "Stopping VM: $vm"
            az vm deallocate --resource-group $RESOURCE_GROUP --name $vm --no-wait
        done
        
        print_status "Waiting 30 seconds for VMs to deallocate..."
        sleep 30
        
        for vm in $VM_LIST; do
            print_status "Deleting VM: $vm"
            az vm delete --resource-group $RESOURCE_GROUP --name $vm --yes --no-wait
        done
    fi
    
    # Delete Azure Firewall
    print_status "Cleaning up Azure Firewall..."
    FIREWALL_LIST=$(az network firewall list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv)
    
    if [ ! -z "$FIREWALL_LIST" ]; then
        for firewall in $FIREWALL_LIST; do
            print_status "Deleting Azure Firewall: $firewall"
            az network firewall delete --resource-group $RESOURCE_GROUP --name $firewall --no-wait
        done
    fi
    
    # Delete Azure Bastion
    print_status "Cleaning up Azure Bastion..."
    BASTION_LIST=$(az network bastion list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv)
    
    if [ ! -z "$BASTION_LIST" ]; then
        for bastion in $BASTION_LIST; do
            print_status "Deleting Azure Bastion: $bastion"
            az network bastion delete --resource-group $RESOURCE_GROUP --name $bastion --no-wait
        done
    fi
    
    # Delete VPN Gateways
    print_status "Cleaning up VPN Gateways..."
    VPN_GW_LIST=$(az network vnet-gateway list --resource-group $RESOURCE_GROUP --query "[].name" --output tsv)
    
    if [ ! -z "$VPN_GW_LIST" ]; then
        for vpn_gw in $VPN_GW_LIST; do
            print_status "Deleting VPN Gateway: $vpn_gw"
            az network vnet-gateway delete --resource-group $RESOURCE_GROUP --name $vpn_gw --no-wait
        done
    fi
    
    print_success "Selective cleanup initiated (running in background)"
    print_status "Expensive resources are being deleted. This may take 10-20 minutes."
    print_status "Check Azure Portal for deletion progress."
}

# Function to perform complete resource group cleanup
cleanup_resource_group() {
    print_warning "This will delete the entire resource group and ALL resources within it!"
    print_warning "Resource group: $RESOURCE_GROUP"
    echo ""
    
    read -p "Are you absolutely sure you want to delete the entire resource group? (type 'DELETE' to confirm): " -r
    echo ""
    
    if [[ $REPLY == "DELETE" ]]; then
        print_status "Deleting resource group: $RESOURCE_GROUP"
        az group delete --name $RESOURCE_GROUP --yes --no-wait
        print_success "Resource group deletion initiated (running in background)"
        print_status "This will take 15-30 minutes. Check Azure Portal for status."
    else
        print_warning "Resource group deletion cancelled"
        exit 0
    fi
}

# Function to check cleanup status
check_cleanup_status() {
    if az group show --name $RESOURCE_GROUP &> /dev/null; then
        RESOURCE_COUNT=$(get_resource_count)
        print_status "Resource group still exists with $RESOURCE_COUNT resources"
        
        if [ "$RESOURCE_COUNT" -gt 0 ]; then
            print_status "Remaining resources:"
            az resource list --resource-group $RESOURCE_GROUP --output table
            echo ""
            estimate_costs
        else
            print_status "Resource group is empty but still exists"
            print_status "You can manually delete the empty resource group from Azure Portal"
        fi
    else
        print_success "Resource group has been completely deleted"
    fi
}

# Function to show help
show_help() {
    echo "Azure Hub-and-Spoke Network Cleanup Tool"
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  --selective    Delete only expensive resources (Firewall, Bastion, VMs)"
    echo "  --complete     Delete entire resource group"
    echo "  --status       Check current cleanup status"
    echo "  --help         Show this help message"
    echo ""
    echo "Interactive mode (no parameters): Shows menu with all options"
}

# Main cleanup function
main() {
    # Handle command line arguments
    case "$1" in
        --selective)
            check_resource_group
            list_resources
            estimate_costs
            cleanup_expensive_resources
            exit 0
            ;;
        --complete)
            check_resource_group
            list_resources
            estimate_costs
            cleanup_resource_group
            exit 0
            ;;
        --status)
            check_cleanup_status
            exit 0
            ;;
        --help)
            show_help
            exit 0
            ;;
    esac

    # Interactive mode
    echo "========================================="
    echo "Azure Hub-and-Spoke Network Cleanup Tool"
    echo "========================================="
    echo ""
    
    # Check prerequisites
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    check_resource_group
    
    # Show current resources
    list_resources
    estimate_costs
    
    echo ""
    echo "Cleanup Options:"
    echo "1. Selective cleanup (delete expensive resources only)"
    echo "2. Complete cleanup (delete entire resource group)"  
    echo "3. Check cleanup status"
    echo "4. Exit"
    echo ""
    
    read -p "Choose an option (1-4): " -n 1 -r
    echo ""
    echo ""
    
    case $REPLY in
        1)
            cleanup_expensive_resources
            ;;
        2)
            cleanup_resource_group
            ;;
        3)
            check_cleanup_status
            ;;
        4)
            print_status "Exiting cleanup tool"
            exit 0
            ;;
        *)
            print_error "Invalid option selected"
            exit 1
            ;;
    esac
}

# Error handling
trap 'print_error "Cleanup script encountered an error"' ERR

# Run main function
main "$@"
