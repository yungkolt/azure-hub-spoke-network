#!/bin/bash

# Configure Network Peering
# Author: yungkolt
# Description: Set up hub-to-spoke and spoke-to-hub peering connections

RESOURCE_GROUP=$1

echo "Configuring Network Peering..."

# Hub to Production Spoke Peering
echo "Setting up Hub <-> Production Spoke peering..."
az network vnet peering create \
    --resource-group $RESOURCE_GROUP \
    --name hub-to-prod \
    --vnet-name vnet-hub-eastus \
    --remote-vnet vnet-prod-eastus \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --allow-gateway-transit

az network vnet peering create \
    --resource-group $RESOURCE_GROUP \
    --name prod-to-hub \
    --vnet-name vnet-prod-eastus \
    --remote-vnet vnet-hub-eastus \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --use-remote-gateways

# Hub to Development Spoke Peering
echo "Setting up Hub <-> Development Spoke peering..."
az network vnet peering create \
    --resource-group $RESOURCE_GROUP \
    --name hub-to-dev \
    --vnet-name vnet-hub-eastus \
    --remote-vnet vnet-dev-eastus \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --allow-gateway-transit

az network vnet peering create \
    --resource-group $RESOURCE_GROUP \
    --name dev-to-hub \
    --vnet-name vnet-dev-eastus \
    --remote-vnet vnet-hub-eastus \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --use-remote-gateways

# Hub to DMZ Spoke Peering
echo "Setting up Hub <-> DMZ Spoke peering..."
az network vnet peering create \
    --resource-group $RESOURCE_GROUP \
    --name hub-to-dmz \
    --vnet-name vnet-hub-eastus \
    --remote-vnet vnet-dmz-eastus \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --allow-gateway-transit

az network vnet peering create \
    --resource-group $RESOURCE_GROUP \
    --name dmz-to-hub \
    --vnet-name vnet-dmz-eastus \
    --remote-vnet vnet-hub-eastus \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --use-remote-gateways

# Verify peering status
echo "Verifying peering connections..."
echo "Hub peering connections:"
az network vnet peering list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub-eastus \
    --output table

echo "Network peering configuration completed"
