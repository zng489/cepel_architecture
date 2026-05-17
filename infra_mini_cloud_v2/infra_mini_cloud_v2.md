# 🏗️ Mini Data Lake — Guia de Replicação
> Guia passo a passo para subir toda a infraestrutura do zero.

---

## 📦 Stack de Serviços

| Serviço | Função | Porta |
|---|---|---|
| RustFS | Storage S3 compatível | 9000 / 9001 |
| S3Browser | UI do RustFS | 9090 |
| Spark Master | Processamento distribuído | 7077 / 8088 |
| Spark Workers (x2) | Workers do Spark | 8081 / 8082 |
| Jupyter | Notebooks interativos | 8888 |
| Apache Polaris | Catálogo Iceberg REST | 8181 |
| OpenMetadata | Governança e linhagem | 8585 |
| PostgreSQL | Backend do OpenMetadata | 5432 |
| Elasticsearch | Search do OpenMetadata | 9201 |

---

## ✅ Pré-requisitos

### 1. Instalar Docker

```bash
sudo apt update
sudo apt install -y docker.io
sudo apt install -y docker-compose-v2
sudo usermod -aG docker $USER
newgrp docker

# Verificar instalação
docker --version
docker compose version
```

---

## PASSO 1 — Subir o RustFS (Storage S3)

> O RustFS roda em rede separada com subnet fixa. Isso é obrigatório pois o container usa IP fixo.

### 1.1 Criar a rede do RustFS

```bash
docker network create \
  --subnet=192.168.100.0/24 \
  --gateway=192.168.100.1 \
  rust-net
```

### 1.2 Subir o RustFS

```bash
cd services/rustfs
docker compose up -d
```

### 1.3 Verificar se subiu

```bash
docker ps | grep rustfs
```

Esperado:
```
rustfs    Up    0.0.0.0:9000-9001->9000-9001/tcp
s3browser Up    0.0.0.0:9090->8080/tcp
```

### 1.4 Credenciais do RustFS

> As credenciais completas estão no `docker-compose.yml` do RustFS. Abra e confira.

| Item | Valor padrão |
|---|---|
| Access Key | `rustfs` |
| Secret Key | `rustfs123` |
| S3 API | http://localhost:9000 |
| Console | http://localhost:9001 |
| S3Browser UI | http://localhost:9090 |

---

## PASSO 2 — Criar o Bucket no RustFS

1. Acesse **http://localhost:9090**
2. Faça login com as credenciais do `docker-compose.yml`
3. Crie um bucket com o nome: **`bronze`**

### Estrutura que será criada nas próximas etapas:

```
bronze/                         ← bucket
└── equipe_dados/               ← namespace
    └── table_1/                ← tabela Iceberg
        ├── metadata/
        │   ├── snap-*.avro
        │   └── v1.metadata.json
        └── data/
            └── *.parquet
```

---

## PASSO 3 — Buildar Imagens Locais

> Alguns serviços usam imagens customizadas com Dockerfile próprio. Elas precisam ser buildadas antes do `docker compose up`.

### 3.1 Build do Spark

```bash
docker build -t spark-master:dev ./services/spark/spark/
```

### 3.2 Build do Jupyter

```bash
cd services/jupyter
docker build -t jupyter:dev .
cd ../..
```

| Imagem | Tag | Diretório |
|---|---|---|
| `spark-master` | `dev` | `./services/spark/spark/` |
| `jupyter` | `dev` | `./services/jupyter/` |

---

## PASSO 4 — Subir Spark, Jupyter, Polaris e OpenMetadata

```bash
cd ~/Desktop/infra_mini_cloud_v1
docker compose up -d
```

### Verificar se todos os containers subiram

```bash
docker ps
```

Esperado:

| Container | Status |
|---|---|
| spark-master | ✅ Up |
| spark-worker-1 | ✅ Up |
| spark-worker-2 | ✅ Up |
| jupyter | ✅ Up |
| polaris | ✅ Healthy |
| openmetadata-server | ✅ Healthy (pode demorar ~2min) |
| openmetadata-postgres | ✅ Healthy |
| om-elasticsearch | ✅ Healthy |

> ⏳ O `openmetadata-server` demora mais para subir pois depende do `migrate` terminar primeiro.

### Acompanhar o migrate

```bash
docker compose logs -f openmetadata-migrate
```

---

## PASSO 5 — Configurar o Polaris

> O Polaris precisa ter um **catalog** e um **namespace** criados antes de usar com o Spark.

### 5.1 Rodar o script de setup

```bash
chmod +x setup_polaris.sh
./setup_polaris.sh
```

Este script irá:
- Gerar o token OAuth2 do Polaris
- Criar o catalog `poc_catalog` apontando para `s3://bronze`
- Criar o namespace (ex: `cepel` ou o de sua escolha)

### 5.2 O que o script cria

```
Polaris
└── poc_catalog  (INTERNAL)
    └── [seu_namespace]
        └── s3://bronze/
```

### 5.3 Personalizar namespace

Edite o `setup_polaris.sh` e altere o campo `namespace` conforme sua necessidade:

```bash
-d '{"namespace":["SEU_NAMESPACE"]}'
```

### 5.4 Verificar catalog criado (opcional)

```bash
TOKEN=$(curl -s -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

curl -s http://localhost:8181/api/management/v1/catalogs \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

---

## PASSO 6 — Configurar o Spark (Copiar JARs)

> O Spark precisa dos JARs do Iceberg (SDK v2) para se comunicar com o Polaris via REST.

### 6.1 Copiar bibliotecas para os containers

```bash
chmod +x copy_jars.sh
./copy_jars.sh
```

Este script copia os seguintes JARs para todos os containers Spark e Jupyter:
- `iceberg-spark-runtime-3.5_2.12-1.5.2.jar`
- `iceberg-aws-bundle-1.5.2.jar`

### 6.2 Verificar se os JARs foram copiados

```bash
docker exec spark-master ls /opt/spark/jars/ | grep iceberg
```

Esperado:
```
iceberg-aws-bundle-1.5.2.jar
iceberg-spark-runtime-3.5_2.12-1.5.2.jar
```

### 6.3 Por que SDK v2?

| | SDK v1 | SDK v2 |
|---|---|---|
| Iceberg REST catalog | ❌ | ✅ |
| Apache Polaris | ❌ | ✅ |
| S3 compatível (RustFS) | Parcial | ✅ |

---

## PASSO 7 — Usar o Jupyter Notebook

### 7.1 Acessar o Jupyter

- Acesse **http://localhost:8888**
- As credenciais (token/senha) estão no `docker-compose.yml` do Jupyter

### 7.2 Iniciar SparkSession

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Iceberg Polaris RustFS") \
    .config("spark.sql.catalog.polaris.warehouse", "poc_catalog") \
    .getOrCreate()

spark.sparkContext.setLogLevel("ERROR")
```

### 7.3 Verificar catalogs e namespaces

```python
spark.sql("SHOW CATALOGS").show()
spark.sql("SHOW NAMESPACES IN polaris").show()
spark.sql("SHOW TABLES IN polaris.cepel").show()
```

### 7.4 Salvar tabela de teste no formato Iceberg

```python
# Criar DataFrame de teste
from pyspark.sql import Row
data = [Row(id=1, nome="Alice"), Row(id=2, nome="Bob")]
df = spark.createDataFrame(data)

# Salvar como tabela Iceberg no Polaris
df.write.format("iceberg").saveAsTable("polaris.cepel.tabela_teste")
```

### 7.5 Ler tabela Iceberg

```python
df = spark.read.format("iceberg").load("polaris.cepel.tabela_teste")
df.show()
```

> ✅ Os dados estarão salvos no bucket `bronze` do RustFS, gerenciados pelo Polaris no formato Iceberg.

---

## PASSO 8 — Configurar o OpenMetadata

### 8.1 Rodar o script de inicialização

```bash
chmod +x start.sh
./start.sh
```

Este script faz automaticamente:
1. Sobe o stack
2. Aguarda o `migrate` terminar
3. Reseta a senha do admin
4. Reinicia o servidor

### 8.2 Verificar o migrate

```bash
docker logs openmetadata-migrate
```

### 8.3 Reindexar o OpenMetadata

```bash
sudo docker exec openmetadata-server \
  /opt/openmetadata/bootstrap/openmetadata-ops.sh reindex
```

### 8.4 Acessar o OpenMetadata

```
URL:      http://localhost:8585
Email:    admin@open-metadata.org
Senha:    admin
```

---

## PASSO 9 — Conectar OpenMetadata ao Polaris (Ingestão)

> Este passo faz o OpenMetadata descobrir automaticamente as tabelas Iceberg do Polaris e exibir linhagem, metadados e governança.

### 9.1 Gerar token do Polaris

```bash
POLARIS_TOKEN=$(curl -sf -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&client_id=root&client_secret=s3cr3t&scope=PRINCIPAL_ROLE:ALL' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

echo "Token: ${POLARIS_TOKEN:0:20}..."
```

> ⚠️ O token expira em ~1h. Sempre gere um novo antes de rodar a ingestão.

### 9.2 Atualizar token do Polaris no YAML

```bash
sed -i "s|          token:.*|          token: \"$POLARIS_TOKEN\"|" iceberg-polaris.yaml
```

### 9.3 Pegar JWT do ingestion-bot

1. Acesse **http://localhost:8585**
2. Vá em **Settings → Bots → ingestion-bot**
3. Gere um novo token JWT
4. Copie o token

### 9.4 Atualizar JWT no YAML

**Opção A — via sed:**
```bash
sed -i "s|jwtToken:.*|jwtToken: \"SEU_JWT_AQUI\"|" iceberg-polaris.yaml
```

**Opção B — via Python (recomendado para tokens longos):**
```python
python3 -c "
import re
token = 'COLE_SEU_JWT_AQUI'
with open('iceberg-polaris.yaml', 'r') as f:
    content = f.read()
content = re.sub(r'jwtToken:.*', f'jwtToken: \"{token}\"', content)
with open('iceberg-polaris.yaml', 'w') as f:
    f.write(content)
print('Feito!')
"
```

### 9.5 Rodar a ingestão

```bash
cd ~/Desktop/infra_mini_cloud_v1/services/openmetadata

sudo docker run -it --rm --network spark-net \
  -v $(pwd)/iceberg-polaris.yaml:/tmp/iceberg-polaris.yaml \
  -v $(pwd)/run_ingest.py:/tmp/run_ingest.py \
  --entrypoint python \
  openmetadata/ingestion:1.6.6 /tmp/run_ingest.py
```

### 9.6 `run_ingest.py` (conteúdo do arquivo)

```python
import yaml
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
```

> ✅ Após a ingestão, as tabelas Iceberg aparecerão no OpenMetadata com linhagem, schema e metadados.

### 9.7 Quando precisar rodar de novo

| Passo | Precisa repetir? |
|---|---|
| Gerar token Polaris | ✅ Sempre (expira ~1h) |
| Atualizar JWT ingestion-bot | ✅ Quando expirar (401) |
| `iceberg-polaris.yaml` | ❌ Fica fixo |
| `run_ingest.py` | ❌ Fica fixo |

---

## 📋 Referência Rápida — Acessos

| Serviço | URL | Credenciais |
|---|---|---|
| Spark Master UI | http://localhost:8088 | — |
| Spark Worker 1 | http://localhost:8081 | — |
| Spark Worker 2 | http://localhost:8082 | — |
| Jupyter | http://localhost:8888 | Ver docker-compose.yml |
| OpenMetadata | http://localhost:8585 | admin / admin |
| Polaris | http://localhost:8181 | root / s3cr3t |
| Elasticsearch | http://localhost:9201 | — |
| S3Browser | http://localhost:9090 | Ver docker-compose.yml |
| RustFS S3 API | http://localhost:9000 | rustfs / rustfs123 |
| RustFS Console | http://localhost:9001 | rustfs / rustfs123 |

---

## ⚠️ Problemas Conhecidos e Soluções

| Problema | Causa | Solução |
|---|---|---|
| `Command 'docker' not found` | Docker não instalado | `sudo apt install -y docker.io` |
| `network rust-net not found` | Rede não criada | Criar rede com subnet (Passo 1.1) |
| `no configured subnet contains IP 192.168.100.10` | Rede criada sem subnet | `docker network rm rust-net` e recriar com subnet |
| `pull access denied for spark-master` | Imagem local não buildada | Rodar `docker build` (Passo 3) |
| `iceberg is not a valid Data Source` | JARs não carregados | Rodar `copy_jars.sh` (Passo 6) |
| `Unable to find warehouse` | Catalog não criado no Polaris | Rodar `setup_polaris.sh` (Passo 5) |
| `STS 403 error` | Polaris tentando AWS STS real | Adicionar `SKIP_CREDENTIAL_SUBSCOPING_INDIRECTION: true` no compose |
| `openmetadata-migrate exit 1` | Banco com dados anteriores | `docker compose down -v && docker compose up -d` |
| Login falha no OpenMetadata | Hash bcrypt inconsistente | Rodar `start.sh` (Passo 8.1) |
| `401 Unauthorized` na ingestão | JWT expirado | Gerar novo JWT em Settings → Bots → ingestion-bot |

---

## 🔄 Resumo Visual do Fluxo

```
┌─────────────────────────────────────────────────────────┐
│                    MINI DATA LAKE                        │
│                                                         │
│  PASSO 1         PASSO 2         PASSO 3                │
│  Criar rede  →  Subir RustFS → Criar bucket bronze      │
│  rust-net                                               │
│      ↓                                                  │
│  PASSO 4         PASSO 5         PASSO 6                │
│  Build imagens → docker       → Setup Polaris           │
│  spark/jupyter   compose up     (catalog + namespace)   │
│      ↓                                                  │
│  PASSO 7         PASSO 8         PASSO 9                │
│  Copy JARs    → Jupyter       → Salvar tabela Iceberg   │
│  (copy_jars.sh)  Notebook       no Polaris              │
│      ↓                                                  │
│  PASSO 10        PASSO 11                               │
│  start.sh     → Ingestão                               │
│  (OpenMetadata)  Polaris → OpenMetadata                 │
│                  (linhagem + metadados) ✅              │
└─────────────────────────────────────────────────────────┘
```
