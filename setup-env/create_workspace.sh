set -e

read -p "Name of the workspace to create: " NEW_WORKSPACE_NAME
if [ -z "$NEW_WORKSPACE_NAME" ]; then
    echo "Workspace name cannot be empty. Exiting."
    exit 1
fi

read -p "Username to assign admin rights to the workspace: " NEW_WORKSPACE_ADMIN_USERNAME
if [ -z "$NEW_WORKSPACE_ADMIN_USERNAME" ]; then
    echo "Workspace admin username cannot be empty. Exiting."
    exit 1
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

export MLFLOW_TRACKING_URI="https://$FQDN"

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

echo "👷‍♀️ Creating workspace..."
uv run python - <<EOF
import mlflow
mlflow.create_workspace(name="${NEW_WORKSPACE_NAME}")
EOF

echo "🔑 Assigning admin role to user '${NEW_WORKSPACE_ADMIN_USERNAME}'..."
uv run python - <<EOF
import mlflow.server
auth_client = mlflow.server.get_app_client("basic-auth", tracking_uri="${MLFLOW_TRACKING_URI}")
roles = auth_client.list_roles("${NEW_WORKSPACE_NAME}")
admin_role = next((role for role in roles if role.name == "admin"), None)
if admin_role is None:
    raise RuntimeError("Admin role not found in the workspace.")
auth_client.assign_role(
    username="${NEW_WORKSPACE_ADMIN_USERNAME}",
    role_id=admin_role.id
)
EOF

echo "✅ Workspace '${NEW_WORKSPACE_NAME}' created successfully."
