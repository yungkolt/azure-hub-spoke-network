#!/bin/bash

# Deploy Hub Network Components

RESOURCE_GROUP=$1
LOCATION=$2

echo "Deploying Hub Virtual Network..."

# Create Hub VNet
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name vnet-hub-eastus \
    --location $LOCATION \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name subnet-gateway \
    --subnet-prefixes 10.0.0.0/27

# Create additional hub subnets
az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub-eastus \
    --name AzureFirewallSubnet \
    --address-prefixes 10.0.1.0/26

az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub-eastus \
    --name AzureBastionSubnet \
    --address-prefixes 10.0.2.0/27

az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub-eastus \
    --name subnet-shared-services \
    --address-prefixes 10.0.3.0/24

echo "Hub network deployment completed"
