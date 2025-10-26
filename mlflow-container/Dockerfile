# MLFlow image with Postgres and Azure Blob Storage support
# Launch with command:
#   /root/start_mlflow_server.sh
# And environment variables:
#   BACKEND_STORE_URI - URI to MLFLOW database
#   ARTIFACT_ROOT - URI to MLFLOW artifact storage
FROM python:3.13-slim

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir mlflow azure-storage-blob

COPY start_mlflow_server.sh /root/start_mlflow_server.sh
RUN chmod u+x /root/start_mlflow_server.sh
