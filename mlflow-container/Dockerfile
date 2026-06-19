# MLFlow image with Postgres and Azure Blob Storage support.
# Launch with command:
#   /root/start_mlflow_server.sh
# And environment variables including (see deploy.sh or MLFlow documentation for options):
#   MLFLOW_BACKEND_STORE_URI
#   MLFLOW_DEFAULT_ARTIFACT_ROOT
#   MLFLOW_PORT
#   MLFLOW_DB_NAME
#   AUTH_DB_CONNECTION_STRING
#   MLFLOW_ADMIN_USERNAME
#   MLFLOW_ADMIN_PASSWORD
FROM python:3.13-slim

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir "mlflow[auth]" azure-storage-blob "psycopg[binary]"

COPY start_mlflow_server.sh /root/start_mlflow_server.sh
RUN chmod u+x /root/start_mlflow_server.sh
EXPOSE 5000
