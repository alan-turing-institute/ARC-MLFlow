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

# Subnet for Private Endpoints (NOT delegated)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name "${RESOURCE_GROUP}-vnet" \
  --name private-endpoints-subnet \
  --address-prefixes 10.0.9.0/24

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

# Create with temporary public access for setup
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
  --public-access 0.0.0.0 \
  --yes

# Add temporary firewall rule for your IP
MY_IP=$(curl -4 https://ifconfig.me)
az postgres flexible-server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER_NAME \
  --rule-name "temp-setup-rule" \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP

echo "📊 Creating MLflow database..."
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_SERVER_NAME \
  --database-name $MLFLOW_DB_NAME

echo "🔐 Creating MLflow authentication database..."
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_SERVER_NAME \
  --database-name $AUTH_DB_NAME

# Get PostgreSQL connection string
POSTGRES_HOST="${POSTGRES_SERVER_NAME}.postgres.database.azure.com"

echo "👤 Creating application DB users and grants..."

# Run SQL commands directly using psql
PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_ADMIN_USER \
  -d postgres \
  -c "CREATE USER \"${MLFLOW_DB_USER}\" WITH PASSWORD '${MLFLOW_DB_USER_PASSWORD}';" \
  || echo "MLflow user may already exist"

PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_ADMIN_USER \
  -d postgres \
  -c "CREATE USER \"${AUTH_DB_USER}\" WITH PASSWORD '${AUTH_DB_USER_PASSWORD}';" \
  || echo "Auth user may already exist"

PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_ADMIN_USER \
  -d postgres \
  -c "GRANT CONNECT ON DATABASE \"${MLFLOW_DB_NAME}\" TO \"${MLFLOW_DB_USER}\";"

PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_ADMIN_USER \
  -d postgres \
  -c "ALTER DATABASE \"${MLFLOW_DB_NAME}\" OWNER TO \"${MLFLOW_DB_USER}\";"

PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_ADMIN_USER \
  -d postgres \
  -c "GRANT CONNECT ON DATABASE \"${AUTH_DB_NAME}\" TO \"${AUTH_DB_USER}\";"

PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_ADMIN_USER \
  -d postgres \
  -c "ALTER DATABASE \"${AUTH_DB_NAME}\" OWNER TO \"${AUTH_DB_USER}\";"

echo "🔒 Securing PostgreSQL - removing public access..."

# Delete the temporary firewall rule
az postgres flexible-server firewall-rule delete \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER_NAME \
  --rule-name "temp-setup-rule" \
  --yes

# Disable public access
az postgres flexible-server update \
  --resource-group $RESOURCE_GROUP \
  --name $POSTGRES_SERVER_NAME \
  --public-access Disabled \
  --yes

# Create private endpoint for VNet integration
echo "🔗 Creating private endpoint for PostgreSQL..."
az network private-endpoint create \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --name "${POSTGRES_SERVER_NAME}-pe" \
  --vnet-name "${RESOURCE_GROUP}-vnet" \
  --subnet private-endpoints-subnet \
  --private-connection-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${POSTGRES_SERVER_NAME}" \
  --group-ids postgresqlServer \
  --connection-name "${POSTGRES_SERVER_NAME}-connection"

# Create private DNS zone for internal resolution
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name "privatelink.postgres.database.azure.com"

# Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "privatelink.postgres.database.azure.com" \
  --name "${RESOURCE_GROUP}-link" \
  --virtual-network "${RESOURCE_GROUP}-vnet" \
  --registration-enabled false


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
MLFLOW_DB_STR="${MLFLOW_DB_NAME} = host=${POSTGRES_HOST} port=5432 user=${MLFLOW_DB_USER} pool_size=150 min_pool_size=15"
AUTH_DB_STR="${AUTH_DB_NAME} = host=${POSTGRES_HOST} port=5432 user=${AUTH_DB_USER} pool_size=30 min_pool_size=3"
DATABASES="${MLFLOW_DB_STR},${AUTH_DB_STR}"

az containerapp create \
  --resource-group $RESOURCE_GROUP \
  --name "${PGBOUNCER_APP_NAME}" \
  --environment $ENVIRONMENT_NAME \
  --image ghcr.io/alan-turing-institute/arc-pgbouncer-image \
  --target-port 5432 \
  --ingress internal \
  --transport tcp \
  --min-replicas 1 \
  --max-replicas 1 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --secrets \
    "databases=${DATABASES}" \
  --env-vars \
    "DATABASES=secretref:databases" \
    "PGBOUNCER_MIN_POOL_SIZE=3" \
    "PGBOUNCER_DEFAULT_POOL_SIZE=30" \
    "PGBOUNCER_MAX_DB_CONNECTIONS=200" \
    "PGBOUNCER_RESERVE_POOL_SIZE=30" \
    "PGBOUNCER_MAX_CLIENT_CONN=600" \
    "PGBOUNCER_LISTEN_ADDR=0.0.0.0" \
    "PGBOUNCER_POOL_MODE=transaction" \
    "PGBOUNCER_SERVER_IDLE_TIMEOUT=600" \
    "PGBOUNCER_AUTH_TYPE=scram-sha-256" \
    "PGBOUNCER_AUTH_QUERY=SELECT usename, passwd FROM pg_shadow WHERE usename=\$1" \
    "PGBOUNCER_SERVER_TLS_SSLMODE=require" \

# Get PgBouncer FQDN for internal communication
PGBOUNCER_FQDN=$(az containerapp show \
  --resource-group $RESOURCE_GROUP \
  --name "${PGBOUNCER_APP_NAME}" \
  --query properties.configuration.ingress.fqdn -o tsv)

# DB connection strings via PgBouncer
DB_CONNECTION_STRING="postgresql+psycopg://${MLFLOW_DB_USER}:${MLFLOW_DB_USER_PASSWORD}@${PGBOUNCER_FQDN}:5432/${MLFLOW_DB_NAME}"
AUTH_DB_CONNECTION_STRING="postgresql+psycopg://${AUTH_DB_USER}:${AUTH_DB_USER_PASSWORD}@${PGBOUNCER_FQDN}:5432/${AUTH_DB_NAME}"

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
