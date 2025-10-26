# MLFlow image with Postgres and Azure Blob Storage support
# Launch with command:
#    mlflow server --backend-store-uri ${BACKEND_STORE_URI} --default-artifact-root ${ARTIFACT_ROOT} --host 0.0.0.0 --serve-artifacts --port 5000
# Replacing the environment variables as needed or using .env/similar.
FROM python:3.13-slim

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir mlflow psycopg2-binary azure-storage-blob

