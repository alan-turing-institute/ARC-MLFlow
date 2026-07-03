# ARC-MLFlow

This repo deploys an MLFlow server to Azure. If you just want to learn about what it deploys, see [here](#components). If you want to use it, keep reading.

**⚠️ Caveats:** Although I've made best efforts, within reason, I cannot assure the security or stability of the server. With an abundance of caution I'd suggest you work under the assumption that:
- Everything logged to MLFlow is public.
  - *Positive version: Access is controlled via an Azure-managed IP allow-list and MLFlow-managed user accounts. However, the server uses basic authentication so your passwords are transmitted in plain (base64 encoded) text - **you must use HTTPS to avoid your credentials being stolen, not HTTP.***
- The server may fail and all data be deleted at any time.
  - *Positive version: The database is an Azure managed service, so we should be able to recover data from there if everything else fails, unless someone accidentally deletes it...*

On that happy note, to get up and running:

1. Install the [pre-requisites](#pre-requisites).
2. If you need to create a new deployment, see the last [creating a new deployment](#creating-a-new-deployment) section.
3. To setup an account and workspace on a pre-existing server, see [MLFlow Account and Workspace setup](#mlflow-account-and-workspace-setup).
4. To interact with a pre-existing server in Python, see [Using MLFlow in Python](#using-mlflow-in-python).

## Pre-requisites

Install the Azure CLI and login, selecting the correct subscription (probably "ARC") as active, and install Python dependencies:

```bash
brew install azure-cli pwgen
az login
uv sync
```

`pwgen` is used to auto-generate passwords.


## MLFlow Account and Workspace Setup

To run these commands you will need to know:

**If using the user interface:**
- The URL of the MLFlow server

**If using the setup scripts:**
  - The Azure resource group the MLFlow server has been deployed into (default: `arc-turing-mlflow`)
  - The name of the MLFlow container app (default: same as the resource group)
  - The Azure CLI installed and logged in (see pre-requisites)
  - A `uv` environment with `mlflow[auth]` installed in it.

Ask the owner of the server for these, or you can get them from the Azure portal yourself.

### User Setup

#### 1. Add an Allowed IP Address

The Turing IP address is automatically added to the allow-list as part of the deployment (which will also be your IP address if you're on the VPN). If you need to add another, run:

```bash
cd setup-env
bash add_ip.sh
```

This will prompt for an IP address/address range to add, and a suitable label for it.

#### 2. Create a user

##### In a browser:

If you are logged in to the MLFlow UI as an admin, you can create users from there by clicking on your username (bottom left) then going to the "Manage" menu.

##### Via the user creation script:

Running the following script:

```bash
cd setup-env
bash add_user.sh
```

Will:

- Prompt for a username and password to create on the MLFlow server
- Ask for the resource group and app name of the deployed MLFlow server
- Create the user on the server
- Save a `.env` file containing the necessary environment variables to set to use it (`MLFLOW_TRACKING_URI`, `MLFLOW_TRACKING_USERNAME`, `MLFLOW_TRACKING_PASSWORD`)

Source the saved `.env` file (`source .env`) before running scripts using `mlflow`, or add them to your `.bash_profile`/`.zprofile`/similar.


#### 3. Create a workspace [if needed]

Experiments and runs on the MLFlow server are grouped under a "workspace". For our purposes we will generally want a separate workspace for each project. To create one:

##### In the browser

If logged in to the MLFlow UI as an admin, the homepage showing the list of workspaces has a "Create new Workspace" button.

##### Workspace creation script

Running the `setup-env/create_workspace.sh` script will prompt for a workspace name and a username to make admin on that workspace, and create the workspace for you using the API.

##### Workspace permissions

User permissions should generally be managed via "roles", which can have multiple users assigned to them. The server is setup so that all users can *read* all workspaces, i.e. all users can see the content of all workspaces, but not create/change anything in them.

When a workspace is created, MLFlow creates two default roles for it - an admin role (which lets users change everything about the workspace including access permissions for it), and a user role (which lets users create experiments in the workspace but doesn't allow them to use/edit other people's experiments).

You may want to create a role with "Edit" access to the workspace for project members, which allows users assigned to it to also use/edit other people's experiments.

## Using MLFlow in Python

General MLFlow documentation is available here: https://mlflow.org/docs/latest/ml/

### 1. Python Dependencies

```bash
uv sync
```

The main ones are:

- `mlflow[auth]`: The Python library for interacting with a MLFlow server
- `psutil`, `nvidia-ml-py`: If you want to log system (CPU, GPU respectively) stats with your job
- `azure-storage-blob`, `azure-identity`: Not required for normal artifact logging (artifact uploads/downloads are proxied through the MLFlow server - see below), but kept for advanced/direct Azure blob access if needed.

The rest of the dependencies in `pyproject.toml` are just for the examples.

⚠️ You need `mlflow[auth]>=3.14,<4` (already pinned in `pyproject.toml`, so `uv sync` will get this for you). Older `mlflow` installs don't support the `--enable-workspaces` server feature this deployment relies on (`mlflow.set_workspace(...)`), so if you're using an existing environment rather than `uv sync`, make sure it's on a compatible version.

### 2. MLFlow Environment Variables

⚠️ These can be automatically obtained/set via the environment setup script described above.

You must have the following environment variables exported in your environment:

- `MLFLOW_TRACKING_URI` - the URL of the MLFlow server
- `MLFLOW_TRACKING_USERNAME` - your MLFlow username
- `MLFLOW_TRACKING_PASSWORD` - your MLFlow password
- You do **not** need `AZURE_STORAGE_CONNECTION_STRING` to log artefacts - the MLFlow server proxies artifact uploads/downloads to Azure Blob storage on your behalf, authenticated the same way as everything else via `MLFLOW_TRACKING_USERNAME`/`MLFLOW_TRACKING_PASSWORD`. If you want to log an artifact locally instead, you can do so by setting the `artifact_location` when creating the MLFlow experiment you are logging results to, e.g. `mlflow.create_experiment("experiment_name", artifact_location="/your/local/path")`.
- `MLFLOW_HTTP_REQUEST_TIMEOUT` - how long (in seconds) the client waits for a response before timing out, default `300`. Set this high because the server can take a while to respond to the first request after scaling up from idle - see [Troubleshooting](#troubleshooting) below.

### 3. Examples

Example scripts you can run:

- `uv run mlflow-examples/hello.py`: Basic logging of a parameter, metric, and artifact.
- `uv run mlflow-examples/train.py`: Automated logging of metrics and models with the HuggingFace transformers Trainer
- `uv run mlflow-examples/sweep.py`: A hyperparameter sweep.

### 4. View runs in the MLFlow UI

If you go to the `MLFLOW_TRACKING_URI` in a browser and enter your username and password you should get to the UI and be able to browse through your tracked experiments and artefacts.

### 5. Troubleshooting

- **Slow or timed-out first request:** The MLFlow server scales down to zero after 15 minutes of inactivity, and takes a while to ramp back up on the next request. If your first call of the session is slow or times out, that's expected - a higher `MLFLOW_HTTP_REQUEST_TIMEOUT` (see above) and/or retrying usually resolves it.
- **401/403 errors:** Usually a wrong or stale `MLFLOW_TRACKING_USERNAME`/`MLFLOW_TRACKING_PASSWORD`, or forgetting to `source` your `.env` file in the current shell.
- **Connection refused/timed out at the network level:** Your IP address is probably not on the allow-list - see [Add an Allowed IP Address](#1-add-an-allowed-ip-address).
- **Forgot your password:** There's no self-service reset. Ask an admin to recreate your account (via the UI or `add_user.sh`).

## Creating a new Deployment

### Components

The main components are:
- Up to 3 parallel MLFlow server instances, running in an Azure container app.
- A managed Azure PostgresQL database for MLFlow data (runs and metrics/parameters logged to them) and user details.
- 1 instance of PgBouncer in an Azure container app, to manage a connection pool to the database.
- An Azure storage account to provide Blob storage for artifacts (models, datasets, etc.)

They connect together roughly like this:

<img src="docs/azure_deployment.png" alt="Azure deployment components diagram" width="768"/>

**Container app autoscaling:**
- The MLFlow and PgBouncer container apps are configured to automatically scale off if they are unused for a period of time (currently 15 minutes). The containers will ramp back up automatically when any request is made to the server, but the first connectiion after the cooldown period will be slow.

**Security:**
- Access to the MLFlow server is IP restricted (via a configurable allowlist in Azure).
- Authentication on the server is managed by MLFlow's built-in `basic-auth`, which allows role-based permissions for users to different resources on the server. If we use/persist servers longer-term we should look at adding SSO.
- The database is only accessible from within the VNet.
- Artifact (blob) storage has public network access disabled entirely and is only reachable from within the VNet via a private endpoint - all artifact access from clients is proxied through the MLFlow server (and so subject to its authentication and IP allow-list), rather than talking to storage directly.

**Estimated Cost:**

The Azure resources created by the defaults in the deployment script are:

| Service | Quantity |
| --- | --- |
| Azure PostgreSQL B1ms with 32GB storage | 1 |
| MLFlow Container Apps (2.0 CPU, 4 GiB RAM) | 0-3 (autoscale) |
| PgBouncer Container App (0.25 CPU, 0.5 GiB RAM) | 0-1 (autoscale) |
| Azure Blob Storage | 1 |
| Private DNS Zone | 2 |
| Private Endpoint | 2 |
| Public IP and Load Balancer | 1 |

Costs will vary significantly based on usage, but to give an approximate range:

- Light usage: £35/month (container apps mostly scaled to 0, ongoing database and networking costs only)
- Heavy usage: £535/month (dominated by MLFlow container costs, if they are scaled to 3 replicas 24/7)


### Container Builds

The `mlflow-container` and `pgbouncer-container` directories contain docker files for MLFlow and PgBouncer. The images are hosted with GitHub container registry, and will be rebuilt whenever a change is pushed to the relevant directory in the repo.

### Azure Deployment

First, edit any variables you would like to in `container-app/.env` - this specifies names, passwords, and IP restrictions for the deployment, for example. Other aspects are hardcoded in `deploy.sh` and the MLFlow/PgBouncer dockerfiles (sorry). Ensure the resource group you're specifying doesn't already exist. By default passwords are auto-generated and access to the MLFlow server is restricted to the deployment IP address.

```bash
cd container-app
bash deploy.sh
```

ℹ️ **Note:** Most components are placed in a single resource group (`arc-turing-mlflow` by default). A load balancer and public IP address are created in a separate, Azure managed, resource group with an `ME_` prefix.

### Updating the Server

🚨 **This has a high chance of breaking things!** 🚨 If MLFlow has released new features or made breaking changes since the last time the server was deployed, re-building the containers, deleting the old MLFlow deployment, and creating a new one is less likely to cause issues (but also not guaranteed).

1. Trigger re-builds via GitHub Actions if necessary
  - [MLFlow image action](https://github.com/alan-turing-institute/ARC-MLFlow/actions/workflows/build_mlflow.yaml)
  - [PG Bouncer image action](https://github.com/alan-turing-institute/ARC-MLFlow/actions/workflows/build_pgbouncer.yaml)

2. Trigger the container app to update:
  ```
  az containerapp update \
  --resource-group arc-turing-mlflow \
  --name arc-turing-mlflow \
  --image ghcr.io/alan-turing-institute/arc-mlflow-image:latest
  ```
  Replace `--name` with either the MLFlow or PG Bouncer container as required, e.g. `arc-turing-mlflow` or `pgbouncer-app` (see `container-app/.env` for defaults).

### Delete the Deployment (and all data!)

```bash
az group delete --name $RESOURCE_GROUP
```

Where `$RESOURCE_GROUP` is the name of the resource group you deployed MLFlow to.
