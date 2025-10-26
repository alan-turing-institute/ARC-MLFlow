az login

export RESOURCE_GROUP="mlflow-apps-group"
export ENVIRONMENT_NAME="mlflow-environment"
export LOCATION="uksouth"

az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --query "properties.provisioningState"

# az containerapp env create \
#   --name $ENVIRONMENT_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --location "$LOCATION" \
#   --query "properties.provisioningState"

# export ENVIRONMENT_ID=$(az containerapp env show \
#   --name $ENVIRONMENT_NAME \
#   --resource-group $RESOURCE_GROUP \
#   --query "id" \
#   --output tsv)

# echo $ENVIRONMENT_ID

export STORAGE_ACCOUNT_NAME="arcmlflowstorage"
az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME \
  --location "$LOCATION" \
  --kind StorageV2 \
  --sku Standard_LRS \
  --enable-large-file-share \
  --query provisioningState

STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query "[0].value" \
  --output tsv)
echo "Storage Account Key is $STORAGE_ACCOUNT_KEY"

# Azure file share for DB
DB_FILE_SHARE_NAME="dbfileshare"
az storage share create --name $DB_FILE_SHARE_NAME \
    --account-name $STORAGE_ACCOUNT_NAME --only-show-errors --output table

export DB_STORAGE_MOUNT_NAME="dbstoragemount"
az containerapp env storage set \
  --access-mode ReadWrite \
  --azure-file-account-name $STORAGE_ACCOUNT_NAME \
  --azure-file-account-key $STORAGE_ACCOUNT_KEY \
  --azure-file-share-name $DB_FILE_SHARE_NAME \
  --storage-name $DB_STORAGE_MOUNT_NAME \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --output table

# Blob storage for artifacts
export ARTIFACTS_CONTAINER_NAME="mlflowartifacts"
az storage container create --name $ARTIFACTS_CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME --only-show-errors --output table

AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv)

# Container registry
# export REGISTRY_NAME="arcmlflowcontainerregistry"
# az acr create --name $REGISTRY_NAME --resource-group $RESOURCE_GROUP --sku Basic --location $LOCATION
# az acr update --name $REGISTRY_NAME --allow-trusted-services true --resource-group $RESOURCE_GROUP
# az acr update --name $REGISTRY_NAME --resource-group $RESOURCE_GROUP --public-network-enabled true

# az acr build -t mlflow --registry $REGISTRY_NAME --resource-group $RESOURCE_GROUP .

# ACI
az container create --resource-group $RESOURCE_GROUP --file containerinstance.yaml

# Deploy

docker volume create mlflowdb
docker compose up --build --force-recreate 

# export CONTAINER_APP_NAME="mlflow-app"
# az containerapp create -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP \
#     --environment $ENVIRONMENT_NAME \
#     --yaml containerapp.yaml \
#     --query properties.configuration.ingress.fqdn

# LOCAL MACHINE
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=arcmlflowartifacts;AccountKey=ZzIq3lYWlG9kIjdKdyBgv31DrXyo36dUmfKGUc+R9gFggzL7jW8KfCCdUEKuG7sjBhzHEtb4gR+6+AStK5Wvzw==;EndpointSuffix=core.windows.net"
uv run src/train.py

