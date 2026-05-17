cat > /tmp/reset.sql << 'EOF'
UPDATE user_entity 
SET json = jsonb_set(
  json::jsonb, 
  '{authenticationMechanism,config,password}', 
  '"$2b$12$8kHgmRQ8zm6s/xpzoaUZ9OCLlsbtv31mwdJsigXqhZ/pfsAQRCotW"'
) 
WHERE json->>'email' = 'admin@open-metadata.org';
EOF

docker exec -i openmetadata-postgres psql -U om_user -d openmetadata_db < /tmp/reset.sql
docker restart openmetadata-server



http://localhost:8585
Email:    admin@open-metadata.org
Password: admin


docker exec -i openmetadata-postgres psql -U om_user -d openmetadata_db -c \
"SELECT json->'authenticationMechanism'->'config'->>'password' FROM user_entity WHERE json->>'email' = 'admin@open-metadata.org';"



(env1) lenovo@lenovo-ThinkPad-E14-Gen-5:~/Desktop/infra_mini_cloud_v1/services$ pip install bcrypt --break-system-packages
python3 -c "import bcrypt; print(bcrypt.hashpw(b'admin', bcrypt.gensalt()).decode())"
Collecting bcrypt
  Downloading bcrypt-5.0.0-cp39-abi3-manylinux_2_34_x86_64.whl.metadata (10 kB)
Downloading bcrypt-5.0.0-cp39-abi3-manylinux_2_34_x86_64.whl (278 kB)
Installing collected packages: bcrypt
Successfully installed bcrypt-5.0.0
$2b$12$y3AyD2ykko81pFQgxYmqxO6R0tbx75Zn6rslSyK2e2.kt/NEAX4AK




cat > /tmp/reset.sql << 'EOF'
UPDATE user_entity 
SET json = jsonb_set(
  json::jsonb, 
  '{authenticationMechanism,config,password}', 
  '"$2b$12$y3AyD2ykko81pFQgxYmqxO6R0tbx75Zn6rslSyK2e2.kt/NEAX4AK"'
) 
WHERE json->>'email' = 'admin@open-metadata.org';
EOF

docker exec -i openmetadata-postgres psql -U om_user -d openmetadata_db < /tmp/reset.sql
docker restart openmetadata-server




Adicione o FERNET_KEY no migrate e uma senha fixa para o admin. Edite o docker-compose.yml do openmetadata:
yamlopenmetadata-migrate:
  image: openmetadata/server:1.6.6
  container_name: openmetadata-migrate
  restart: "no"
  depends_on:
    openmetadata-postgres:
      condition: service_healthy
  entrypoint: ["./bootstrap/openmetadata-ops.sh", "migrate"]
  environment:
    DB_DRIVER_CLASS: org.postgresql.Driver
    DB_SCHEME: postgresql
    DB_HOST: openmetadata-postgres
    DB_PORT: "5432"
    DB_USER: om_user
    DB_USER_PASSWORD: om_user_pass
    OM_DATABASE: openmetadata_db
    DB_PARAMS: "sslmode=disable"
    FERNET_KEY: jJgVqL9KpHx8t4YzW2mNcR5sA7bDfG1kU3oX6eQ0vBw=  # ← adicionar
  networks:
    - spark-net
Depois:
bashdocker compose down -v
docker compose up -d
Aguardar migrate terminar e rodar reset de senha uma última vez:
bashcat > /tmp/reset.sql << 'EOF'
UPDATE user_entity 
SET json = jsonb_set(
  json::jsonb, 
  '{authenticationMechanism,config,password}', 
  '"$2b$12$y3AyD2ykko81pFQgxYmqxO6R0tbx75Zn6rslSyK2e2.kt/NEAX4AK"'
) 
WHERE json->>'email' = 'admin@open-metadata.org';
EOF

docker exec -i openmetadata-postgres psql -U om_user -d openmetadata_db < /tmp/reset.sql
docker restart openmetadata-server
Depois disso não precisará mais resetar — a FERNET_KEY ficará consistente entre o migrate e o server.





isso tbm12:15 AMClaude respondeu: Sim!Sim! Sempre que subir do zero (down -v) precisaria resetar a senha.
A solução definitiva é criar um script que faz tudo automaticamente:
bash#!/bin/bash
set -e

echo "=== Subindo stack ==="
docker compose down -v
docker compose up -d

echo "=== Aguardando migrate terminar ==="
until docker inspect openmetadata-migrate --format='{{.State.Status}}' | grep -q "exited"; do
  echo "... aguardando migrate ..."
  sleep 5
done

echo "=== Resetando senha admin ==="
HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'admin', bcrypt.gensalt()).decode())")

cat > /tmp/reset.sql << EOF
UPDATE user_entity 
SET json = jsonb_set(
  json::jsonb, 
  '{authenticationMechanism,config,password}', 
  '"$HASH"'
) 
WHERE json->>'email' = 'admin@open-metadata.org';
EOF

docker exec -i openmetadata-postgres psql -U om_user -d openmetadata_db < /tmp/reset.sql
docker restart openmetadata-server

echo "=== Pronto! ==="
echo "Acesse: http://localhost:8585"
echo "Email:  admin@open-metadata.org"
echo "Senha:  admin"
Salve como start.sh na raiz do projeto e rode:
bashchmod +x start.sh
./start.sh
Assim nunca mais precisará fazer isso manualmente.


Acessando o token bot pelo bash

# Codificar senha em base64
PASS=$(echo -n "admin" | base64)

# Login
curl -s -X POST http://localhost:8585/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@open-metadata.org\",\"password\":\"$PASS\"}"


eyJraWQiOiJHYjM4OWEtOWY3Ni1nZGpzLWE5MmotMDI0MmJrOTQzNTYiLCJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJvcGVuLW1ldGFkYXRhLm9yZyIsInN1YiI6ImluZ2VzdGlvbi1ib3QiLCJyb2xlcyI6WyJJbmdlc3Rpb25Cb3RSb2xlIl0sImVtYWlsIjoiaW5nZXN0aW9uLWJvdEBvcGVuLW1ldGFkYXRhLm9yZyIsImlzQm90Ijp0cnVlLCJ0b2tlblR5cGUiOiJCT1QiLCJpYXQiOjE3Nzg5ODU2MjksImV4cCI6bnVsbH0.SltRM7Ja-6OhUztf0SESohmYe-en6J9AGg6uALPDl1GPC6LopMwgbEQvkIV3V4xdh9n6OPrxv_28o43hPaSOqPaaLfHP--3uCeK5g_cv6RnOF_wLEXE77nY17Fl85xkaZo-IY8pnvhNVXmzCOnc77tfHQwQ4tcuwTzWZ5ATk5LDrS0fgZ_zn9kSiLW3iiFX5b6wkwimTLlDLkoJAauoNoSQdkfsoj3ebAHkIRugyETKF07vk5Uw-pQPD_j0ErHgE6wt_Ooz8KB8K8IFK0K7oenGv2XoJOMHeYOYEhNZlMUpwOOdREYQHT5CG4fUl5ju7CO5-Jus7KJesZCYz9gbaXA





cd ~/Desktop/infra_mini_cloud_v1/services/openmetadata

# 1. Token Polaris fresco
POLARIS_TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

# 2. Atualizar tokens no YAML
sed -i "s|token:.*|token: \"$POLARIS_TOKEN\"|" iceberg-polaris.yaml
sed -i "s|jwtToken:.*|jwtToken: \"eyJraWQiOiJHYjM4OWEtOWY3Ni1nZGpzLWE5MmotMDI0MmJrOTQzNTYiLCJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJvcGVuLW1ldGFkYXRhLm9yZyIsInN1YiI6ImluZ2VzdGlvbi1ib3QiLCJyb2xlcyI6WyJJbmdlc3Rpb25Cb3RSb2xlIl0sImVtYWlsIjoiaW5nZXN0aW9uLWJvdEBvcGVuLW1ldGFkYXRhLm9yZyIsImlzQm90Ijp0cnVlLCJ0b2tlblR5cGUiOiJCT1QiLCJpYXQiOjE3Nzg5ODU2MjksImV4cCI6bnVsbH0.SltRM7Ja-6OhUztf0SESohmYe-en6J9AGg6uALPDl1GPC6LopMwgbEQvkIV3V4xdh9n6OPrxv_28o43hPaSOqPaaLfHP--3uCeK5g_cv6RnOF_wLEXE77nY17Fl85xkaZo-IY8pnvhNVXmzCOnc77tfHQwQ4tcuwTzWZ5ATk5LDrS0fgZ_zn9kSiLW3iiFX5b6wkwimTLlDLkoJAauoNoSQdkfsoj3ebAHkIRugyETKF07vk5Uw-pQPD_j0ErHgE6wt_Ooz8KB8K8IFK0K7oenGv2XoJOMHeYOYEhNZlMUpwOOdREYQHT5CG4fUl5ju7CO5-Jus7KJesZCYz9gbaXA\"|" iceberg-polaris.yaml

# 3. Rodar ingestão
docker run -it --rm --network spark-net \
  -v $(pwd)/iceberg-polaris.yaml:/tmp/iceberg-polaris.yaml \
  -v $(pwd)/run_ingest.py:/tmp/run_ingest.py \
  --entrypoint python \
  openmetadata/ingestion:1.6.6 /tmp/run_ingest.py






  # Deletar todos os índices do OpenMetadata
curl -s -X DELETE "http://localhost:9201/*search_index*"
curl -s -X DELETE "http://localhost:9201/dataAsset"

# Reiniciar o servidor
docker restart openmetadata-server





PASS=$(echo -n "admin" | base64)
ACCESS_TOKEN=$(curl -s -X POST http://localhost:8585/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@open-metadata.org\",\"password\":\"$PASS\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["accessToken"])')

curl -s -X POST "http://localhost:8585/api/v1/apps/trigger/SearchIndexingApplication" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recreateIndex": true}'





docker restart openmetadata-server

sleep 60

PASS=$(echo -n "admin" | base64)
ACCESS_TOKEN=$(curl -s -X POST http://localhost:8585/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@open-metadata.org\",\"password\":\"$PASS\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["accessToken"])')

curl -s -X POST "http://localhost:8585/api/v1/apps/trigger/SearchIndexingApplication" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recreateIndex": true}'





  sudo docker exec openmetadata-server /opt/openmetadata/bootstrap/openmetadata-ops.sh reindex




  me dá detalhe e isnturção de passo a passo pq funcionou2:20 AMClaude responded: Boa!Boa! Aqui o passo a passo completo do que fizemos:

Pré-requisitos

Polaris rodando em localhost:8181
OpenMetadata rodando em openmetadata-server:8585
Ambos na rede Docker spark-net


Passo 1 — Pega o token do Polaris
bashPOLARIS_TOKEN=$(curl -sf -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
echo "Token: ${POLARIS_TOKEN:0:20}..."
O Polaris emite tokens de curta duração (~1h), então esse passo precisa ser repetido toda vez.

Passo 2 — Atualiza o token do Polaris no YAML
bashsed -i "s|          token:.*|          token: \"$POLARIS_TOKEN\"|" iceberg-polaris.yaml

Passo 3 — Pega o JWT do ingestion-bot no OpenMetadata
Acessa http://localhost:8585 → Settings → Bots → ingestion-bot → gera token.
O token do OpenMetadata também expira (depende da configuração), então quando der 401 é só gerar um novo lá.

Passo 4 — Atualiza o JWT no YAML
bashsed -i "s|jwtToken:.*|jwtToken: \"SEU_JWT_AQUI\"|" iceberg-polaris.yaml

Passo 5 — Corrige o run_ingest.py
pythonimport yaml
from metadata.workflow.metadata import MetadataWorkflow

def run():
    with open("/tmp/iceberg-polaris.yaml", "r") as f:
        workflow_config = yaml.safe_load(f)
    workflow = MetadataWorkflow.create(workflow_config)
    workflow.execute()
    workflow.raise_from_status()
    workflow.print_status()
    workflow.stop()

if __name__ == "__main__":
    run()
A versão 1.6.6 usa MetadataWorkflow (não Workflow), e o create() recebe um dicionário Python, não um caminho de arquivo.

Passo 6 — Roda a ingestão
bashsudo docker run -it --rm --network spark-net \
  -v $(pwd)/iceberg-polaris.yaml:/tmp/iceberg-polaris.yaml \
  -v $(pwd)/run_ingest.py:/tmp/run_ingest.py \
  --entrypoint python \
  openmetadata/ingestion:1.6.6 /tmp/run_ingest.py

Quando precisar rodar de novo, os únicos passos que mudam são o 1 (token do Polaris expira) e o 3 (JWT do OpenMetadata expira). O YAML e o run_ingest.py ficam fixos.