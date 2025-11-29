#!/bin/bash
# MLflow on Azure Container Apps - Deployment Script
# Features: HTTPS, IP restrictions, Basic Auth, PostgreSQL, Blob Storage

#############
# ENVIRONMENT
#############
set -e
echo "Loading environment variables from .env file"
set -a; source .env; set +a

az extension add --name containerapp --upgrade

# ============================================================================
# DEPLOYMENT
# ============================================================================
echo "🚀 Deploying MLflow on Azure Container Apps..."

# Create resource group
echo "📦 Creating resource group..."
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# ============================================================================
# Virtual Network Setup
# ============================================================================
echo "🌐 Creating Virtual Network..."
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name "${RESOURCE_GROUP}-vnet" \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16

# Subnet for Container Apps
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "${RESOURCE_GROUP}-vnet" \
  --name container-apps-subnet \
  --address-prefixes 10.0.0.0/21 \
  --delegations Microsoft.App/environments

# Subnet for PostgreSQL (delegated)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "${RESOURCE_GROUP}-vnet" \
  --name postgres-subnet \
  --address-prefixes 10.0.8.0/24 \
  --delegations Microsoft.DBforPostgreSQL/flexibleServers

# Get subnet IDs
CONTAINER_SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "${RESOURCE_GROUP}-vnet" \
  --name container-apps-subnet \
  --query id -o tsv)

POSTGRES_SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "${RESOURCE_GROUP}-vnet" \
  --name postgres-subnet \
  --query id -o tsv)

# ============================================================================
# PostgreSQL Database
# ============================================================================

echo "🗄️  Creating PostgreSQL Flexible Server..."
az provider register --namespace Microsoft.DBforPostgreSQL
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER_NAME \
  --location $LOCATION \
  --admin-user $POSTGRES_ADMIN_USER \
  --admin-password "$POSTGRES_ADMIN_PASSWORD" \
  --sku-name Standard_B2s \
  --tier Burstable \
  --version 14 \
  --storage-size 32 \
  --vnet "${RESOURCE_GROUP}-vnet" \
  --subnet postgres-subnet \
  --yes

echo "📊 Creating MLflow database..."
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_SERVER_NAME \
  --database-name $MLFLOW_DB_NAME

# Get PostgreSQL connection string
POSTGRES_HOST="${POSTGRES_SERVER_NAME}.postgres.database.azure.com"

echo "🔐 Creating MLflow authentication database..."
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_SERVER_NAME \
  --database-name $AUTH_DB_NAME

# ============================================================================
# Storage Account (Artifact Store)
# ============================================================================

echo "💾 Creating Storage Account..."
az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2

# Get storage account key and connection string
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv)

AZURE_STORAGE_ACCESS_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv)

echo "📁 Creating blob container for artifacts..."
az storage container create \
  --account-name $STORAGE_ACCOUNT_NAME \
  --name $STORAGE_CONTAINER_NAME \
  --connection-string $AZURE_STORAGE_CONNECTION_STRING

ARTIFACT_URI="wasbs://${STORAGE_CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/"

# ============================================================================
# Deploy Container Apps Environment
# ============================================================================
echo "🌐 Creating Container Apps Environment..."
az containerapp env create \
  --resource-group $RESOURCE_GROUP \
  --name $ENVIRONMENT_NAME \
  --location $LOCATION \
  --infrastructure-subnet-resource-id $CONTAINER_SUBNET_ID \
  --internal-only false

# ============================================================================
# Deploy PgBouncer Container App
# ============================================================================
echo "🔄 Deploying PgBouncer connection pooler..."
AZURE_PG_USER="${POSTGRES_ADMIN_USER}@${POSTGRES_SERVER_NAME}"
DATABASE_URLS="postgresql://${AZURE_PG_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/${MLFLOW_DB_NAME},postgresql://${AZURE_PG_USER}:${POSTGRES_ADMIN_PASSWORD}@${POSTGRES_HOST}:5432/${AUTH_DB_NAME}"

az containerapp create \
  --resource-group $RESOURCE_GROUP \
  --name "${PGBOUNCER_APP_NAME}" \
  --environment $ENVIRONMENT_NAME \
  --image edoburu/pgbouncer:latest \
  --target-port 5432 \
  --ingress internal \
  --transport tcp \
  --min-replicas 1 \
  --max-replicas 1 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --secrets \
    "database-urls=${DATABASE_URLS}" \
  --env-vars \
    "DATABASE_URLS=secretref:database-urls" \
    "MIN_POOL_SIZE=5" \
    "DEFAULT_POOL_SIZE=150" \
    "MAX_DB_CONNECTIONS=200" \
    "RESERVE_POOL_SIZE=100" \
    "MAX_CLIENT_CONN=1000" \
    "LISTEN_ADDR=0.0.0.0" \
    "POOL_MODE=transaction" \
    "SERVER_IDLE_TIMEOUT=600" \
    "AUTH_TYPE=trust" \
    "SERVER_TLS_SSLMODE=require" \

# Get PgBouncer FQDN for internal communication
PGBOUNCER_FQDN=$(az containerapp show \
  --resource-group $RESOURCE_GROUP \
  --name "${PGBOUNCER_APP_NAME}" \
  --query properties.configuration.ingress.fqdn -o tsv)

# DB connection strings via PgBouncer
DB_CONNECTION_STRING="postgresql+psycopg://${POSTGRES_ADMIN_USER}@${PGBOUNCER_APP_NAME}:5432/${MLFLOW_DB_NAME}"
AUTH_DB_CONNECTION_STRING="postgresql+psycopg://${POSTGRES_ADMIN_USER}@${PGBOUNCER_APP_NAME}:5432/${AUTH_DB_NAME}"

# ============================================================================
# Deploy MLflow Container App
# ============================================================================
echo "🐳 Deploying MLflow Container App..."
az containerapp create \
  --resource-group $RESOURCE_GROUP \
  --name $CONTAINER_APP_NAME \
  --environment $ENVIRONMENT_NAME \
  --image ghcr.io/alan-turing-institute/arc-mlflow-image \
  --target-port 5000 \
  --ingress external \
  --min-replicas 0 \
  --max-replicas 3 \
  --cpu 1.0 \
  --memory 2.0Gi \
  --secrets \
    "admin-username=${MLFLOW_ADMIN_USERNAME}" \
    "admin-password=${MLFLOW_ADMIN_PASSWORD}" \
    "auth-db-conn-str=${AUTH_DB_CONNECTION_STRING}" \
    "auth-secret-key=${MLFLOW_FLASK_SERVER_SECRET_KEY}" \
    "backend-store-uri=${DB_CONNECTION_STRING}" \
    "default-artifact-root=${ARTIFACT_URI}" \
    "storage-conn-str=${AZURE_STORAGE_CONNECTION_STRING}" \
    "storage-access-key=${AZURE_STORAGE_ACCESS_KEY}" \
  --env-vars \
    "AZURE_STORAGE_CONNECTION_STRING=secretref:storage-conn-str" \
    "AZURE_STORAGE_ACCESS_KEY=secretref:storage-access-key" \
    "MLFLOW_BACKEND_STORE_URI=secretref:backend-store-uri" \
    "MLFLOW_DEFAULT_ARTIFACT_ROOT=secretref:default-artifact-root" \
    "MLFLOW_DB_NAME=${MLFLOW_DB_NAME}" \
    "AUTH_DB_CONNECTION_STRING=secretref:auth-db-conn-str" \
    "MLFLOW_ADMIN_USERNAME=secretref:admin-username" \
    "MLFLOW_ADMIN_PASSWORD=secretref:admin-password" \
    "MLFLOW_FLASK_SERVER_SECRET_KEY=secretref:auth-secret-key" \
    "MLFLOW_PORT=5000" \
  --command "/root/start_mlflow_server.sh"

# Apply IP restrictions
echo "🔒 Applying IP restrictions..."
az containerapp ingress access-restriction set \
  --resource-group $RESOURCE_GROUP \
  --name $CONTAINER_APP_NAME \
  --rule-name "allowed-ips" \
  --ip-address $ALLOWED_IPS \
  --action Allow

# Get the FQDN
FQDN=$(az containerapp show \
  --resource-group $RESOURCE_GROUP \
  --name $CONTAINER_APP_NAME \
  --query properties.configuration.ingress.fqdn -o tsv)

# ============================================================================
# Output Information
# ============================================================================

echo ""
echo "✅ MLflow Deployment Complete"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 MLflow Tracking Server"
echo "URL:              https://${FQDN}"
echo "Resource Group:   ${RESOURCE_GROUP}"
echo "Location:         ${LOCATION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Network Configuration"
echo "✓ Allowed IPs: ${ALLOWED_IPS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💾 Storage"
echo "Database:         ${POSTGRES_SERVER_NAME}"
echo "PgBouncer:        ${PGBOUNCER_FQDN}"
echo "Storage Account:  ${STORAGE_ACCOUNT_NAME}"
echo "Artifacts:        ${ARTIFACT_URI}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "👥 MLFlow Admin Account"
echo "Username: ${MLFLOW_ADMIN_USERNAME}"
echo "Password: ${MLFLOW_ADMIN_PASSWORD}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✨ Deployment complete. Access your MLflow server at: https://${FQDN}"
