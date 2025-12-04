#!/bin/bash

echo "🔍 Debugging connection strings..."
echo "MLFLOW_BACKEND_STORE_URI: ${MLFLOW_BACKEND_STORE_URI}"
echo "AUTH_DB_CONNECTION_STRING: ${AUTH_DB_CONNECTION_STRING}"
echo "MLFLOW_DB_NAME: ${MLFLOW_DB_NAME}"

echo $AUTH_CONFIG_BASE64 | base64 -d > /tmp/basic_auth.ini

export MLFLOW_AUTH_CONFIG_PATH="/tmp/basic_auth.ini"

cat > $MLFLOW_AUTH_CONFIG_PATH << EOF
[${MLFLOW_DB_NAME}]
default_permission = READ
database_uri = ${AUTH_DB_CONNECTION_STRING}
admin_username = ${MLFLOW_ADMIN_USERNAME}
admin_password = ${MLFLOW_ADMIN_PASSWORD}

EOF


mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri $MLFLOW_BACKEND_STORE_URI \
    --default-artifact-root $MLFLOW_DEFAULT_ARTIFACT_ROOT \
    --app-name basic-auth \
    --serve-artifacts \
    --allowed-hosts "*"
