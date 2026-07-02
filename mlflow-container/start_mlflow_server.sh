#!/bin/bash
# Laaunch script for the MLFLow server, called as the final command in the mlflow-container Dockerfile
export MLFLOW_AUTH_CONFIG_PATH="/tmp/basic_auth.ini"

cat > $MLFLOW_AUTH_CONFIG_PATH << EOF
[${MLFLOW_DB_NAME}]
default_permission = READ
grant_default_workspace_access = true
database_uri = ${AUTH_DB_CONNECTION_STRING}
admin_username = ${MLFLOW_ADMIN_USERNAME}
admin_password = ${MLFLOW_ADMIN_PASSWORD}

EOF


mlflow server \
    --host 0.0.0.0 \
    --port $MLFLOW_PORT \
    --backend-store-uri $MLFLOW_BACKEND_STORE_URI \
    --default-artifact-root $MLFLOW_DEFAULT_ARTIFACT_ROOT \
    --app-name basic-auth \
    --serve-artifacts \
    --enable-workspaces
