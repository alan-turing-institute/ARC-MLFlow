# ARC-MLFlow

## Pre-requisites

```bash
brew install azure-cli
```

```bash
az login
```

```bash
brew install pwgen
```

## Deployment

### MLFlow Container Build

### Azure Deployment

```bash
az login
```

```bash
cd container-app-deployment
bash deploy.sh
```

#### Delete the Deployment (and all data!)

```bash
az group delete --name $RESOURCE_GROUP
```

Where `$RESOURCE_GROUP` is the name of the resource group where you deployed MLFlow on Azure.

## Using MLFlow

### Python Dependencies

```bash
uv sync
```

The main ones are:

- `mlflow`: The Python library for interacting with a MLFlow server
- `psutil`, `"nvidia-ml-py`: If you want to log system (CPU, GPU respectively) stats with your job
- `azure-storage-blob`: If you want to log artifacts (files, e.g. models), as these are stored in an Azure blob.
- `hyperopt`: Is the package MLFlow recommends for hyperparameter sweeps.

The rest of the dependencies in `pyproject.toml` are just for the examples.

### MLFlow Environment Variables

```bash
export MLFLOW_TRACKING_URI="<TRACKING_URI>"
```

e.g.

```bash
export MLFLOW_TRACKING_URI="http://$(az container show --resource-group ${RESOURCE_GROUP} --name mlflow-aci --query ipAddress.fqdn -o tsv):5000/"
```

or `mlflow.set_tracking_uri("http://0.0.0.0:5000")`

### Logging Artifacts

If you want your script to save artifacts (files, models etc.), the default location for the MLFlow server is an Azure blob. To be able to do this you must have the connection string for the Azure blob set as an environment variable where your script is running. You can get it as follows:

```bash
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv)
```

If you want to log an artifact locally instead, you should be able to do so by setting the `artifact_location` when creating the MLFlow experiment you are logging results to, e.g. `mlflow.create_experiment("experiment_name", artifact_location="/your/local/path")`.

### Examples

The scripts in `mlflow-examples` give a few examples of using MLFlow.

To start:

1. Find the name of the MLFlow resource group in the ARC subscription in the Azure portal (https://portal.azure.com), e.g. `arc-mlflow-test`.

2. Find the name of the MLFLow container app, e.g. `mlflow-app`.

3. Set the correct values for these in the first two lines of `mlflow-examples/.env`.

4. Load the environment variables:
   ```bash
   cd mlflow-examples
   source .env
   ```

Example scripts you can run:

- `uv run mlflow-examples/hello.py`: Basic logging of a parameter, metric, and artifact.
- `uv run mlflow-examples/train.py`: Automated logging of metrics and models with the HuggingFace transformers Trainer
- `uv run mlflow-examples/sweep.py`: A hyperparameter sweep.
