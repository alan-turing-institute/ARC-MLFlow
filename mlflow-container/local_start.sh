set -a; source .env; set +a
docker volume create mlflowdb
docker compose up --build --force-recreate 