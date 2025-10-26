#!/bin/bash
mlflow server --backend-store-uri ${BACKEND_STORE_URI} --default-artifact-root ${ARTIFACT_ROOT} --host 0.0.0.0 --serve-artifacts --port 5000 --allowed-hosts "*"