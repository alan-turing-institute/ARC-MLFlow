# exit on fail
set -e

#############
# ENVIRONMENT
#############
echo "Loading environment variables from .env file"
set -a; source .env; set +a

echo "Starting Azure deployment"

################
# RESOURCE GROUP
################
echo "Creating resource group: $RESOURCE_GROUP in $LOCATION"
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --query "properties.provisioningState"

#########
# STORAGE
#########
echo "Creating storage account: $STORAGE_ACCOUNT_NAME"
az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME \
  --location "$LOCATION" \
  --kind StorageV2 \
  --sku Standard_LRS \
  --enable-large-file-share \
  --query provisioningState

export STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query "[0].value" \
  --output tsv)
echo "Storage Account Key is $STORAGE_ACCOUNT_KEY"

export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv)

# Azure file share for DB
echo "Creating Azure file share: $DB_FILE_SHARE_NAME"
az storage share create \
    --name $DB_FILE_SHARE_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --output table \
    --quota 10 \
    --connection-string $AZURE_STORAGE_CONNECTION_STRING


# Blob storage for artifacts
echo "Creating Blob storage container: $ARTIFACTS_CONTAINER_NAME"
az storage container create \
  --name $ARTIFACTS_CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  --output table \
  --connection-string $AZURE_STORAGE_CONNECTION_STRING

##########
# NETWORK
##########
echo "Creating Virtual Network: $VNET_NAME"
az network vnet create \
  --name $VNET_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --address-prefixes 10.0.0.0/16

echo "Creating NSG: ${SUBNET_NAME}-nsg"
az network nsg create \
  --resource-group $RESOURCE_GROUP \
  --name $NSG_NAME \
  --location $LOCATION

# Get your public IP
MY_IP=$(curl -4 https://ifconfig.me)
ALLOWED_IPS="${MY_IP} ${ALLOWED_SOURCE_IPS}"

echo "Creating NSG rule to allow access from: $ALLOWED_IPS"
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name $NSG_NAME \
  --name AllowMLflowFromAllowedIPs \
  --priority 100 \
  --source-address-prefixes $ALLOWED_IPS \
  --destination-port-ranges 5000 \
  --access Allow \
  --protocol Tcp

echo "Creating subnet with NSG"
az network vnet subnet create \
  --name $SUBNET_NAME \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --address-prefixes 10.0.0.0/24 \
  --delegations Microsoft.ContainerInstance/containerGroups \
  --network-security-group $NSG_NAME

export SUBNET_ID=$(az network vnet subnet show \
  --name $SUBNET_NAME \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --query id \
  --output tsv)
echo "Subnet ID is $SUBNET_ID"

# echo "Creating Public IP: $IP_NAME"
# az network public-ip create \
#   --name $IP_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --location $LOCATION \
#   --allocation-method Static \
#   --sku Standard \
#   --dns-name $DNS_NAME

##########
# Firewall
##########
# echo "Creating subnet for Azure Firewall"
# az network vnet subnet create \
#   --name AzureFirewallSubnet \
#   --resource-group $RESOURCE_GROUP \
#   --vnet-name $VNET_NAME \
#   --address-prefixes 10.0.1.0/26

# az extension add --name azure-firewall

# echo "Creating Azure Firewall: $FIREWALL_NAME"
# az network firewall create \
#   --name $FIREWALL_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --location $LOCATION

# # Wait for firewall to finish provisioning
# az network firewall wait \
#   --name $FIREWALL_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --created

# echo "Creating Public IP for Azure Firewall: $IP_NAME"
# az network public-ip create \
#   --name $IP_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --location $LOCATION \
#   --allocation-method static \
#   --sku standard \
#   --dns-name $DNS_NAME

# # Wait for Public IP to be ready
# az network public-ip wait \
#   --name $IP_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --created

# echo "Creating IP Configuration for Azure Firewall: $IP_CONFIG_NAME"
# az network firewall ip-config create \
#   --firewall-name $FIREWALL_NAME \
#   --name $IP_CONFIG_NAME \
#   --public-ip-address $IP_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --vnet-name $VNET_NAME

# az network firewall wait \
#   --name $FIREWALL_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --updated

# echo "Updating Azure Firewall config"
# az network firewall update \
#   --name $FIREWALL_NAME \
#   --resource-group $RESOURCE_GROUP

# az network firewall wait \
#   --name $FIREWALL_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --updated

# FIREWALL_PRIVATE_IP=$(az network firewall ip-config list \
#   --resource-group $RESOURCE_GROUP \
#   --firewall-name $FIREWALL_NAME \
#   --query "[].privateIpAddress" \
#   --output tsv)
# echo "Firewall Private IP is $FIREWALL_PRIVATE_IP"

# FIREWALL_PUBLIC_IP=$(az network public-ip show \
#   --name $IP_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --query ipAddress \
#   --output tsv)
# echo "Firewall Public IP is $FIREWALL_PUBLIC_IP"

# echo "Creating network route table for firewall"
# az network route-table create \
#   --name $ROUTE_TABLE_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --location $LOCATION \
#   --disable-bgp-route-propagation true

# echo "Creating route to direct all traffic through the firewall"
# az network route-table route create \
#   --resource-group $RESOURCE_GROUP \
#   --name DG-Route \
#   --route-table-name $ROUTE_TABLE_NAME \
#   --address-prefix 0.0.0.0/0 \
#   --next-hop-type VirtualAppliance \
#   --next-hop-ip-address $FIREWALL_PRIVATE_IP

# echo "Associating route table with ACI subnet"
# az network vnet subnet update \
#   --name $SUBNET_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --vnet-name $VNET_NAME \
#   --address-prefixes 10.0.0.0/24 \
#   --route-table $ROUTE_TABLE_NAME

# echo "Creating network rule to allow outbound traffic to Azure Storage"
# az network firewall network-rule create \
#   --resource-group $RESOURCE_GROUP \
#   --firewall-name $FIREWALL_NAME \
#   --collection-name outbound-storage \
#   --priority 200 \
#   --action Allow \
#   --name AllowStorage \
#   --protocols TCP \
#   --source-addresses 10.0.0.0/24 \
#   --destination-addresses Storage AzureActiveDirectory AzureResourceManager \
#   --destination-ports 443 445

# echo "Creating network rule to allow outbound traffic to GHCR"
# az network firewall application-rule create \
#   --resource-group $RESOURCE_GROUP \
#   --firewall-name $FIREWALL_NAME \
#   --collection-name outbound-registries \
#   --priority 210 \
#   --action Allow \
#   --name AllowGhcr \
#   --protocols Https=443 \
#   --source-addresses 10.0.0.0/24 \
#   --target-fqdns ghcr.io github.com pkg-containers.githubusercontent.com

# echo "Creating network rule to allow ACI management traffic"
# az network firewall network-rule create \
#   --resource-group $RESOURCE_GROUP \
#   --firewall-name $FIREWALL_NAME \
#   --collection-name outbound-aci-mgmt \
#   --priority 100 \
#   --action Allow \
#   --name AllowACIMgmt \
#   --protocols TCP \
#   --source-addresses 10.0.0.0/24 \
#   --destination-addresses AzureCloud \
#   --destination-ports 443

# echo "Creating network rule to allow DNS traffic to Azure DNS resolver"
# az network firewall network-rule create \
#   --resource-group $RESOURCE_GROUP \
#   --firewall-name $FIREWALL_NAME \
#   --collection-name outbound-azure-dns \
#   --priority 225 \
#   --action Allow \
#   --name AllowDNS \
#   --protocols UDP TCP \
#   --source-addresses 10.0.0.0/24 \
#   --destination-addresses 168.63.129.16 \
#   --destination-ports 53

# az network firewall wait \
#   --name $FIREWALL_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --updated

####################
# CONTAINER INSTANCE
####################
echo "Filling in ACI deployment template"
export BACKEND_STORE_URI="sqlite:///data/mlflow.db"
export ARTIFACT_ROOT="wasbs://${ARTIFACTS_CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/artifacts"

# replace placeholders in aci_template.yaml with environment variable values (including secrets)
awk '{
  line = $0
  for (n in ENVIRON) {
    v = ENVIRON[n]
    gsub(/&/, "\\&", v)              # make & literal in replacement
    gsub("<" n ">", v, line)         # replace <NAME> with $NAME if set
  }
  print line
}' aci_template.yaml > aci_template_filled.yaml

printf '# THIS FILE CONTAINS SECRETS - DO NOT COMMIT IT TO VERSION CONTROL!\n\n' \
    | cat - aci_template_filled.yaml > "temp.yaml" \
    && mv temp.yaml aci_template_filled.yaml

echo "Creating Azure Container Instance from template"
az container create \
  --resource-group $RESOURCE_GROUP \
  --file aci_template_filled.yaml

# echo "Creating NAT rule to allow access to MLflow server"
# ACI_PRIVATE_IP=$(az container show \
#   --name $ACI_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --query ipAddress.ip \
#   --output tsv)
# MY_IP_ADDRESS=$(curl -4 https://ifconfig.me)
# ALLOWED_SOURCE_IPS="${MY_IP_ADDRESS} ${ALLOWED_SOURCE_IPS}"
# az network firewall nat-rule create \
#   --firewall-name $FIREWALL_NAME \
#   --collection-name $NAT_COLLECTION_NAME \
#   --action dnat \
#   --name $NAT_RULE_NAME \
#   --protocols TCP \
#   --source-addresses $ALLOWED_SOURCE_IPS \
#   --destination-addresses $FIREWALL_PUBLIC_IP \
#   --destination-ports 5000 \
#   --resource-group $RESOURCE_GROUP \
#   --translated-address $ACI_PRIVATE_IP \
#   --translated-port 5000 \
#   --priority 200

# Get the MLflow Tracking URI
MLFLOW_FQDN=$(az network public-ip show \
  --resource-group $RESOURCE_GROUP \
  --name $IP_NAME \
  --query dnsSettings.fqdn \
  --output tsv)
export MLFLOW_TRACKING_URI="http://${MLFLOW_FQDN}:5000/"
echo "MLflow Tracking URI is $MLFLOW_TRACKING_URI"

echo "Deployment complete!"
