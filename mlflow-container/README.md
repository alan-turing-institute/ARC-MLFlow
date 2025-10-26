# mlflow-container

## GitHub Package

Any changes pushed to this directory will trigger a GitHub actions that rebuilds the MLFlow `Dockerfile` (currently for Linux AMD64 only).

## Local Start

This runs the MLFlow server and database locally, but saving artifacts to remote Azure blob storage.

Create a `.env` file in this directory definining the following environment variables:

```bash
AZURE_STORAGE_CONNECTION_STRING="<your_storage_account_connectino_string>"
BACKEND_STORE_URI="postgresql+psycopg2://<your_db_user>:<your_db_password>@db:5432/mlflow"
ARTIFACT_ROOT="wasbs://artifacts@<your_storage_account_name>.blob.core.windows.net/<your_storage_container_name>"
POSTGRES_USER="mlflowuser"
POSTGRES_PASSWORD="<your_db_password>"
POSTGRES_DB="mlflow"
```
