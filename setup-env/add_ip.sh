read -p "Azure Deployment Resource Group [default: arc-turing-mlflow]: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
    RESOURCE_GROUP="arc-turing-mlflow"
fi

read -p "Azure Container App Name [default: $RESOURCE_GROUP]: " CONTAINER_APP_NAME
if [ -z "$CONTAINER_APP_NAME" ]; then
    CONTAINER_APP_NAME="$RESOURCE_GROUP"
fi

read -p "IP Address or Range to Add : " IP_RANGE
if [ -z "$IP_RANGE" ]; then
    echo "❌ IP Address Range is required. Exiting."
    exit 1
fi

read -p "Name for the new IP Rule: " RULE_NAME
if [ -z "$RULE_NAME" ]; then
    echo "❌ Rule Name is required. Exiting."
    exit 1
fi

echo "🔍 Adding IP rule $RULE_NAME..."
az containerapp ingress access-restriction set \
  --resource-group $RESOURCE_GROUP \
  --name $CONTAINER_APP_NAME \
  --rule-name "$RULE_NAME" \
  --ip-address "$IP_RANGE" \
  --action Allow

echo "✅ Successfully allowed '$IP_RANGE'"
