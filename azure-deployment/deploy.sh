# load environment variables from .env file
echo "Loading environment variables from .env file"
set -a; source .env; set +a

# Create resource group
echo "Creating resource group: $RESOURCE_GROUP in $LOCATION"
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --query "properties.provisioningState"

# Create storage account
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

# Azure file share for DB
echo "Creating Azure file share: $DB_FILE_SHARE_NAME"
az storage share create --name $DB_FILE_SHARE_NAME \
    --account-name $STORAGE_ACCOUNT_NAME --output table


# Blob storage for artifacts
echo "Creating Blob storage container: $ARTIFACTS_CONTAINER_NAME"
az storage container create --name $ARTIFACTS_CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME --output table

export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv)

# ACI
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

echo '# THIS FILE CONTAINS SECRETS - DO NOT COMMIT IT TO VERSION CONTROL!\n' | cat - aci_template_filled.yaml > "temp.yaml" && mv temp.yaml aci_template_filled.yaml

echo "Creating Azure Container Instance from template"
az container create --resource-group $RESOURCE_GROUP --file aci_template_filled.yaml

export MLFLOW_TRACKING_URI="http://$(az container show --resource-group ${RESOURCE_GROUP} --name mlflow-aci --query ipAddress.fqdn -o tsv):5000/"
echo "MLflow Tracking URI is $MLFLOW_TRACKING_URI"
