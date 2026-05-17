#!/bin/bash
set -e

echo "=== Limpando containers antigos ==="
docker rm -f om-elasticsearch openmetadata-postgres openmetadata-server openmetadata-migrate 2>/dev/null || true
docker compose down -v

echo "=== Subindo stack ==="
docker compose up -d

echo "=== Aguardando migrate terminar ==="
until docker inspect openmetadata-migrate --format='{{.State.Status}}' 2>/dev/null | grep -q "exited"; do
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
echo "chmod +x start.sh   ./start.sh"