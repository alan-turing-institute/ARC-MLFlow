# ARC-MLFlow

Azure MLFlow deployment and instructions for how to use it.

## Pre-requisites

Install the Azure CLI and login, selecting the correct subscription (probably "ARC") as active:

```bash
brew install azure-cli pwgen
az login
```

`pwgen` is used to auto-generate passwords.

## Environment Setup

To run these commands you will need to know:

- The Azure resource group the MLFlow server has been deployed into (default: `arc-turing-mlflow`)
- The name of the MLFlow container app (default: same as the resource group)

### MLFlow User Setup and Environment Variables

Running the following script:

```bash
cd setup-env
bash make_env.sh
```

Will:

- Prompt for a username and password to create on the MLFlow server
- Ask for the resource group and app name of the deployed MLFlow server
- Create the user on the server, and save a `.env` file containing the necessary environment variables to set to use it (`MLFLOW_TRACKING_URI`, `AZURE_STORAGE_CONNECTION_STRING`, `MLFLOW_TRACKING_USERNAME`, `MLFLOW_TRACKING_PASSWORD`)

Run `source .env` file before running scripts using `mlflow`, or add them to your `.bash_profile`/`.zprofile`/similar.

### Add an Allowed IP Address

The Turing IP address is automatically added to the allow-list with the deployment. If you need to add another, run:

```bash
cd setup-env
bash add_ip.sh
```

This will prompt for an IP address/address range to add, and a suitable label for it.

## Using MLFlow

⚠️ The MLFlow server will automatically scale off if unused for a period of time (currently 15 minutes). The containers will ramp back up automatically when requested, but the first connectiion after the cooldown period will be slow.

### Python Dependencies

```bash
uv sync
```

The main ones are:

- `mlflow`: The Python library for interacting with a MLFlow server
- `psutil`, `nvidia-ml-py`: If you want to log system (CPU, GPU respectively) stats with your job
- `azure-storage-blob`, `azure-identity`: If you want to log artifacts (files, e.g. models), as these are stored in an Azure blob.
- `hyperopt`: Is the package MLFlow recommends for hyperparameter sweeps.

The rest of the dependencies in `pyproject.toml` are just for the examples.

### MLFlow Environment Variables

⚠️ These can be automatically obtained/set via the environment setup script described above.

You must have the following environment variables exported in your environment:

- `MLFLOW_TRACKING_URI` - the URL of the MLFlow server
- `MLFLOW_TRACKING_USERNAME` - your MLFlow username
- `MLFLOW_TRACKING_PASSWORD` - your MLFlow password
- `AZURE_STORAGE_CONNECTION_STRING` - the connection string for the Azure storage account for artefacts (only needed if you're logging artefacts to Azure). If you want to log an artifact locally instead, you should be able to do so by setting the `artifact_location` when creating the MLFlow experiment you are logging results to, e.g. `mlflow.create_experiment("experiment_name", artifact_location="/your/local/path")`.

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

### The MLFlow UI

If you go to the `MLFLOW_TRACKING_URI` in a browser and enter your username and password you should get to the UI and be able to browser through your tracked experiments and artefacts.

The server automatically scales to zero if

## Deployment

### Container Builds

The `mlflow-container` and `pgbouncer-container` directories contain docker files for MLFlow and PgBouncer (for managing connections to the database). The images are hosted with the GitHub container registry, and will be rebuilt whenever a change is pushed to the relevant directory in the repo.

### Azure Deployment

First, edit any variables you would like to in `container-app/.env` - this specifies names, passwords, and IP restrictions for the deployment, for example. Ensure the resource group you're specifying doesn't already exist. By default passwords are auto-generated and access to the MLFlow server is restricted to the deployment IP address.

```bash
cd container-app-deployment
bash deploy.sh
```

#### Delete the Deployment (and all data!)

```bash
az group delete --name $RESOURCE_GROUP
```

Where `$RESOURCE_GROUP` is the name of the resource group you deployed MLFlow to.
