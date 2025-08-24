#!/bin/bash

# Configure Route Tables and Traffic Control
# Author: yungkolt
# Description: Set up custom routing to direct traffic through Azure Firewall

RESOURCE_GROUP=$1

echo "Configuring Route Tables..."

# Get Azure Firewall private IP
echo "Getting Azure Firewall private IP..."
FIREWALL_IP=$(az network firewall show \
    --resource-group $RESOURCE_GROUP \
    --name fw-hub-eastus \
    --query ipConfigurations[0].privateIPAddress \
    --output tsv)

if [ -z "$FIREWALL_IP" ]; then
    echo "Error: Could not retrieve Azure Firewall IP address"
    exit 1
fi

echo "Azure Firewall private IP: $FIREWALL_IP"

# Create route table for spoke networks
echo "Creating route table for spoke traffic..."
az network route-table create \
    --resource-group $RESOURCE_GROUP \
    --name rt-spoke-to-firewall \
    --location eastus

# Create route to send internet traffic to Azure Firewall
az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-spoke-to-firewall \
    --name route-to-internet-via-firewall \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

# Create routes for spoke-to-spoke communication via firewall
az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-spoke-to-firewall \
    --name route-prod-to-dev \
    --address-prefix 10.2.0.0/16 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-spoke-to-firewall \
    --name route-prod-to-dmz \
    --address-prefix 10.3.0.0/16 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

# Create separate route table for development spoke
az network route-table create \
    --resource-group $RESOURCE_GROUP \
    --name rt-dev-spoke \
    --location eastus

# Development spoke routes
az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-dev-spoke \
    --name route-to-internet-via-firewall \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-dev-spoke \
    --name route-dev-to-prod \
    --address-prefix 10.1.0.0/16 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

# Create route table for DMZ spoke
az network route-table create \
    --resource-group $RESOURCE_GROUP \
    --name rt-dmz-spoke \
    --location eastus

# DMZ spoke routes (minimal routing for public services)
az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-dmz-spoke \
    --name route-dmz-to-prod \
    --address-prefix 10.1.0.0/16 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

az network route-table route create \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-dmz-spoke \
    --name route-dmz-to-dev \
    --address-prefix 10.2.0.0/16 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_IP

# Associate route tables with subnets
echo "Associating route tables with subnets..."

# Production spoke subnets
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-web-tier \
    --route-table rt-spoke-to-firewall

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-app-tier \
    --route-table rt-spoke-to-firewall

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-data-tier \
    --route-table rt-spoke-to-firewall

# Development spoke subnets
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dev-eastus \
    --name subnet-dev-resources \
    --route-table rt-dev-spoke

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dev-eastus \
    --name subnet-dev-testing \
    --route-table rt-dev-spoke

# DMZ spoke subnets  
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dmz-eastus \
    --name subnet-public-services \
    --route-table rt-dmz-spoke

# Display routing configuration
echo ""
echo "Route Tables Created:"
echo "===================="
az network route-table list --resource-group $RESOURCE_GROUP --output table

echo ""
echo "Routes in rt-spoke-to-firewall:"
az network route-table route list \
    --resource-group $RESOURCE_GROUP \
    --route-table-name rt-spoke-to-firewall \
    --output table

echo "Routing configuration completed successfully!"
echo "All spoke traffic will now be routed through Azure Firewall at IP: $FIREWALL_IP"
