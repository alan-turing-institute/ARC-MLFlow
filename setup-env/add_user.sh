# Create a new MLFlow user and save the environment details to a .env file
set -e

echo "User and server details for new MLFlow user creation:"
read -p "MLFlow Username [default: $USER]: " NEW_USERNAME
if [ -z "$NEW_USERNAME" ]; then
    NEW_USERNAME=$USER
fi

read -p "MLFlow Password [default: auto-generate]: " -s NEW_PASSWORD
if [ -z "$NEW_PASSWORD" ]; then
    echo ""
    NEW_PASSWORD=$(pwgen 32 1)
fi

read -p "MLFlow Client Timeout (seconds) [default: 300]: " MLFLOW_HTTP_REQUEST_TIMEOUT
if [ -z "$MLFLOW_HTTP_REQUEST_TIMEOUT" ]; then
    MLFLOW_HTTP_REQUEST_TIMEOUT=300
fi

read -p "Azure Deployment Resource Group [default: arc-turing-mlflow]: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
    RESOURCE_GROUP="arc-turing-mlflow"
fi

read -p "Azure Container App Name [default: $RESOURCE_GROUP]: " CONTAINER_APP_NAME
if [ -z "$CONTAINER_APP_NAME" ]; then
    CONTAINER_APP_NAME="$RESOURCE_GROUP"
fi

echo "🔍 Retrieving MLFlow server URI..."
FQDN=$(az containerapp show \
  --resource-group $RESOURCE_GROUP \
  --name $CONTAINER_APP_NAME \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

MLFLOW_TRACKING_URI="https://$FQDN"

echo "🔐 Retrieving MLFlow admin credentials..."
export MLFLOW_TRACKING_USERNAME=$(az containerapp secret show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_APP_NAME \
    --secret-name "admin-username" \
    --query value \
    --output tsv)

export MLFLOW_TRACKING_PASSWORD=$(az containerapp secret show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_APP_NAME \
    --secret-name "admin-password" \
    --query value \
    --output tsv)

echo "🧑‍🧑‍🧒 Creating new MLFlow user"
uv run python - <<EOF
import mlflow.server
auth_client = mlflow.server.get_app_client("basic-auth", tracking_uri="${MLFLOW_TRACKING_URI}")
auth_client.create_user(username="${NEW_USERNAME}", password="${NEW_PASSWORD}")
EOF

echo "💾 Saving environment details"
cat > .env<< EOF
set -a
MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI}"
MLFLOW_TRACKING_USERNAME="${NEW_USERNAME}"
MLFLOW_TRACKING_PASSWORD="${NEW_PASSWORD}"
MLFLOW_HTTP_REQUEST_TIMEOUT="${MLFLOW_HTTP_REQUEST_TIMEOUT}"
set +a
EOF
echo "✅ MLFlow environment details saved to .env"
