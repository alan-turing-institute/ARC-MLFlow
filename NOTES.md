## What didn't work

- Persisting a postgres database using an Azure file share, due to issues with file permissions/ownership.
- Maybe it would work with a NFS file share, but these can't be mounted in an Azure Container Instance, it seems. It could be mounted in an Azure Container App. To create one (would also need to setup networking):
  ```bash
    az storage account create \
    --resource-group $RESOURCE_GROUP \
    --name $DB_STORAGE_ACCOUNT_NAME \
    --location "$LOCATION" \
    --kind FileStorage \
    --sku Premium_LRS \
    --query provisioningState

    export DB_STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $DB_STORAGE_ACCOUNT_NAME \
    --query "[0].value" \
    --output tsv)
    echo "DB Storage Account Key is $DB_STORAGE_ACCOUNT_KEY"

    az storage share-rm create --storage-account $DB_STORAGE_ACCOUNT_NAME  -g $RESOURCE_GROUP  -n $DB_FILE_SHARE_NAME --enabled-protocols NFS
  ```