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
auth_cache_ttl_seconds = 3600
auth_cache_max_size = 10000

EOF


mlflow server \
    --host 0.0.0.0 \
    --port $MLFLOW_PORT \
    --backend-store-uri $MLFLOW_BACKEND_STORE_URI \
    --artifacts-destination $MLFLOW_ARTIFACTS_DESTINATION \
    --app-name basic-auth \
    --serve-artifacts \
    --enable-workspaces \
    --gunicorn-opts "--threads=8" \

