#!/bin/bash
set -e

echo "=== Gerando token Polaris ==="
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

echo "=== Criando catalog poc_catalog ==="
curl -s -X POST http://localhost:8181/api/management/v1/catalogs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Polaris-Realm: POLARIS" \
  -d '{
    "catalog": {
      "name": "poc_catalog",
      "type": "INTERNAL",
      "readOnly": false,
      "properties": {"default-base-location": "s3://bronze"},
      "storageConfigInfo": {
        "storageType": "S3",
        "allowedLocations": ["s3://bronze"],
        "endpoint": "http://rustfs:9000",
        "pathStyleAccess": true,
        "region": "us-east-1"
      }
    }
  }' | python3 -m json.tool

echo "=== Criando namespace cepel ==="
curl -s -X POST http://localhost:8181/api/catalog/v1/poc_catalog/namespaces \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Polaris-Realm: POLARIS" \
  -d '{"namespace":["equipe_dados"]}' | python3 -m json.tool

echo "=== Verificando ==="
curl -s http://localhost:8181/api/management/v1/catalogs \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo "=== Pronto chmod +x setup_polaris.sh  ./setup_polaris.sh  dentro da pasta do polaris==="