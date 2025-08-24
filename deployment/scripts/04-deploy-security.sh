#!/bin/bash

# Deploy Security Components
# Author: yungkolt
# Description: Deploy Azure Firewall, NSGs, and Bastion Host

RESOURCE_GROUP=$1
LOCATION=$2

echo "Deploying Security Components..."

# Create Network Security Groups
echo "Creating Network Security Groups..."

# Web Tier NSG
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-web-tier \
    --location $LOCATION

# Allow HTTP/HTTPS inbound
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-web-tier \
    --name allow-web-traffic \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-port-ranges 80 443

# Allow SSH from Bastion subnet only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-web-tier \
    --name allow-ssh-from-bastion \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.0.2.0/27 \
    --source-port-ranges '*' \
    --destination-port-ranges 22

# App Tier NSG
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-app-tier \
    --location $LOCATION

# Allow traffic from web tier only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-app-tier \
    --name allow-web-to-app \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.1.1.0/24 \
    --source-port-ranges '*' \
    --destination-port-ranges 8080

# Allow SSH from Bastion subnet only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-app-tier \
    --name allow-ssh-from-bastion \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.0.2.0/27 \
    --source-port-ranges '*' \
    --destination-port-ranges 22

# Data Tier NSG
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-data-tier \
    --location $LOCATION

# Allow database traffic from app tier only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-data-tier \
    --name allow-app-to-data \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.1.2.0/24 \
    --source-port-ranges '*' \
    --destination-port-ranges 1433 3306 5432

# Allow SSH from Bastion subnet only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-data-tier \
    --name allow-ssh-from-bastion \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.0.2.0/27 \
    --source-port-ranges '*' \
    --destination-port-ranges 22

# Dev Environment NSG
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-dev-resources \
    --location $LOCATION

# Allow development traffic (more permissive for testing)
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-dev-resources \
    --name allow-dev-traffic \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol '*' \
    --source-address-prefixes 10.2.0.0/16 \
    --source-port-ranges '*' \
    --destination-port-ranges '*'

# Allow SSH from Bastion subnet only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-dev-resources \
    --name allow-ssh-from-bastion \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.0.2.0/27 \
    --source-port-ranges '*' \
    --destination-port-ranges 22

# DMZ NSG
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-public-services \
    --location $LOCATION

# Allow HTTP/HTTPS from internet
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-public-services \
    --name allow-internet-web \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes 'Internet' \
    --source-port-ranges '*' \
    --destination-port-ranges 80 443

# Associate NSGs with subnets
echo "Associating NSGs with subnets..."
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-web-tier \
    --network-security-group nsg-web-tier

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-app-tier \
    --network-security-group nsg-app-tier

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-prod-eastus \
    --name subnet-data-tier \
    --network-security-group nsg-data-tier

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dev-eastus \
    --name subnet-dev-resources \
    --network-security-group nsg-dev-resources

az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-dmz-eastus \
    --name subnet-public-services \
    --network-security-group nsg-public-services

# Deploy Azure Firewall
echo "Deploying Azure Firewall..."

# Create public IP for Azure Firewall
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name pip-azure-firewall \
    --location $LOCATION \
    --allocation-method Static \
    --sku Standard

# Create Azure Firewall Policy
az network firewall policy create \
    --resource-group $RESOURCE_GROUP \
    --name fw-policy-hub \
    --location $LOCATION

# Create Azure Firewall
az network firewall create \
    --resource-group $RESOURCE_GROUP \
    --name fw-hub-eastus \
    --location $LOCATION \
    --vnet-name vnet-hub-eastus \
    --firewall-policy fw-policy-hub

# Configure Azure Firewall IP Configuration
az network firewall ip-config create \
    --resource-group $RESOURCE_GROUP \
    --firewall-name fw-hub-eastus \
    --name firewall-config \
    --public-ip-address pip-azure-firewall \
    --vnet-name vnet-hub-eastus

# Add basic firewall rules
echo "Configuring Azure Firewall rules..."

# Create rule collection group
az network firewall policy rule-collection-group create \
    --resource-group $RESOURCE_GROUP \
    --policy-name fw-policy-hub \
    --name DefaultApplicationRuleCollectionGroup \
    --priority 300

# Allow outbound web traffic
az network firewall policy rule-collection-group collection add-filter-collection \
    --resource-group $RESOURCE_GROUP \
    --policy-name fw-policy-hub \
    --rule-collection-group-name DefaultApplicationRuleCollectionGroup \
    --name AllowWeb \
    --collection-priority 100 \
    --action Allow \
    --rule-name AllowHTTPS \
    --rule-type ApplicationRule \
    --description "Allow HTTPS traffic" \
    --protocols Https=443 Http=80 \
    --source-addresses 10.1.0.0/16 10.2.0.0/16 10.3.0.0/16 \
    --target-fqdns "*"

# Deploy Azure Bastion
echo "Deploying Azure Bastion..."

# Create public IP for Bastion
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name pip-bastion \
    --location $LOCATION \
    --allocation-method Static \
    --sku Standard

# Create Bastion Host
az network bastion create \
    --resource-group $RESOURCE_GROUP \
    --name bastion-hub \
    --public-ip-address pip-bastion \
    --vnet-name vnet-hub-eastus \
    --location $LOCATION \
    --sku Standard

echo "Security components deployment completed"

# Display deployed security resources
echo ""
echo "Deployed Security Resources:"
echo "============================"
az network nsg list --resource-group $RESOURCE_GROUP --output table
echo ""
az network firewall list --resource-group $RESOURCE_GROUP --output table
echo ""
az network bastion list --resource-group $RESOURCE_GROUP --output table
