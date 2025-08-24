#!/bin/bash

# Deploy Spoke Networks
# Author: yungkolt
# Description: Deploy production, development, and DMZ spoke networks

RESOURCE_GROUP=$1
LOCATION=$2

echo "Deploying Spoke Virtual Networks..."

# Deploy Production Spoke
echo "Creating Production Spoke..."
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name vnet-prod-eastus \
    --location $LOCATION \
    --address-prefixes 10.1.0.0/16 \
    --subnet-name subnet-web-tier \
    --subnet-prefixes 10.1.1.0/24

# Add additional production subnets
az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-app-tier \
    --address-prefixes 10.1.2.0/24

az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-data-tier \
    --address-prefixes 10.1.3.0/24

# Deploy Development Spoke
echo "Creating Development Spoke..."
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name vnet-dev-eastus \
    --location $LOCATION \
    --address-prefixes 10.2.0.0/16 \
    --subnet-name subnet-dev-resources \
    --subnet-prefixes 10.2.1.0/24

# Add additional development subnet for testing
az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dev-eastus \
    --name subnet-dev-testing \
    --address-prefixes 10.2.2.0/24

# Deploy DMZ Spoke
echo "Creating DMZ Spoke..."
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name vnet-dmz-eastus \
    --location $LOCATION \
    --address-prefixes 10.3.0.0/16 \
    --subnet-name subnet-public-services \
    --subnet-prefixes 10.3.1.0/24

# Add WAF subnet for Application Gateway
az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dmz-eastus \
    --name subnet-waf \
    --address-prefixes 10.3.2.0/24

echo "Spoke networks deployment completed"
