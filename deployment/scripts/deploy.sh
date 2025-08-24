#!/bin/bash

# Azure Hub-and-Spoke Network Deployment Script
# Author: yungkolt
# Description: Automated deployment of hub-and-spoke network architecture

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="rg-hub-spoke-network"
LOCATION="eastus"
DEPLOYMENT_NAME="hub-spoke-deployment-$(date +%Y%m%d-%H%M%S)"

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    
    print_success "Prerequisites check passed"
    print_status "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

# Function to create resource group
create_resource_group() {
    print_status "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --output none
    
    print_success "Resource group created successfully"
}

# Function to deploy hub network
deploy_hub() {
    print_status "Deploying hub network..."
    ./01-deploy-hub.sh $RESOURCE_GROUP $LOCATION
    print_success "Hub network deployed successfully"
}

# Function to deploy spoke networks
deploy_spokes() {
    print_status "Deploying spoke networks..."
    ./02-deploy-spokes.sh $RESOURCE_GROUP $LOCATION
    print_success "Spoke networks deployed successfully"
}

# Function to configure peering
configure_peering() {
    print_status "Configuring network peering..."
    ./03-configure-peering.sh $RESOURCE_GROUP
    print_success "Network peering configured successfully"
}

# Function to deploy security components
deploy_security() {
    print_status "Deploying security components..."
    ./04-deploy-security.sh $RESOURCE_GROUP $LOCATION
    print_success "Security components deployed successfully"
}

# Function to configure routing
configure_routing() {
    print_status "Configuring routing tables..."
    ./05-configure-routing.sh $RESOURCE_GROUP
    print_success "Routing configured successfully"
}

# Function to deploy monitoring
deploy_monitoring() {
    print_status "Deploying monitoring components..."
    ./06-deploy-monitoring.sh $RESOURCE_GROUP $LOCATION
    print_success "Monitoring components deployed successfully"
}

# Function to validate deployment
validate_deployment() {
    print_status "Validating deployment..."
    
    # Check if key resources exist
    HUB_VNET=$(az network vnet show --resource-group $RESOURCE_GROUP --name "vnet-hub-eastus" --query name -o tsv 2>/dev/null || echo "")
    if [ -z "$HUB_VNET" ]; then
        print_error "Hub virtual network not found"
        return 1
    fi
    
    PROD_VNET=$(az network vnet show --resource-group $RESOURCE_GROUP --name "vnet-prod-eastus" --query name -o tsv 2>/dev/null || echo "")
    if [ -z "$PROD_VNET" ]; then
        print_error "Production virtual network not found"
        return 1
    fi
    
    print_success "Deployment validation passed"
}

# Function to display deployment summary
show_summary() {
    print_status "Deployment Summary"
    echo "=================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Deployment Name: $DEPLOYMENT_NAME"
    echo ""
    
    print_status "Deployed Resources:"
    az resource list --resource-group $RESOURCE_GROUP --output table
    
    echo ""
    print_success "Hub-and-Spoke network deployment completed successfully!"
    print_status "Check the Azure portal for detailed resource information."
}

# Main deployment function
main() {
    echo "======================================"
    echo "Azure Hub-and-Spoke Network Deployment"
    echo "======================================"
    echo ""
    
    check_prerequisites
    
    # Confirm deployment
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user"
        exit 0
    fi
    
    # Start deployment
    START_TIME=$(date +%s)
    
    create_resource_group
    deploy_hub
    deploy_spokes
    configure_peering
    deploy_security
    configure_routing
    deploy_monitoring
    validate_deployment
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    show_summary
    print_success "Total deployment time: $((DURATION / 60)) minutes and $((DURATION % 60)) seconds"
}

# Error handling
trap 'print_error "Deployment failed. Check the logs for details."' ERR

# Run main function
main "$@"
