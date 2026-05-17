# 🏗️ Mini Data Lake — Arquitetura Completa

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                         🏗️  MINI DATA LAKE — ARQUITETURA                        ║
╚══════════════════════════════════════════════════════════════════════════════════╝

 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                            🌐 REDES DOCKER                                  │
 │                                                                             │
 │   ┌─────────────────────────────┐   ┌───────────────────────────────────┐  │
 │   │         rust-net            │   │            spark-net              │  │
 │   │   subnet: 192.168.100.0/24  │   │         (rede principal)          │  │
 │   │   gateway: 192.168.100.1    │   │                                   │  │
 │   └─────────────────────────────┘   └───────────────────────────────────┘  │
 └─────────────────────────────────────────────────────────────────────────────┘

╔══════════════════════════════════════════════════════════════════════════════════╗
║  🟥  CAMADA DE STORAGE — RustFS (rede: rust-net)                                ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║   ┌──────────────────────────────┐     ┌──────────────────────────────────┐     ║
║   │         RustFS               │     │          S3Browser               │     ║
║   │   S3 API  → :9000            │     │   UI Web  → :9090                │     ║
║   │   Console → :9001            │     │   (gerenciar buckets)            │     ║
║   │                              │     │                                  │     ║
║   │   user: rustfs               │     │   acessa o RustFS visualmente    │     ║
║   │   pass: rustfs123            │     │                                  │     ║
║   └──────────────────────────────┘     └──────────────────────────────────┘     ║
║                                                                                  ║
║   📦 Bucket: bronze/                                                             ║
║      └── equipe_dados/          ← namespace                                     ║
║          └── table_1/           ← tabela Iceberg                                ║
║              ├── metadata/      ← snap-*.avro, v1.metadata.json                 ║
║              └── data/          ← *.parquet                                     ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
                              ▲                ▲
                              │  S3 API        │  S3 API
                              │  (path-style)  │  (path-style)
╔══════════════════════════════╪════════════════╪═════════════════════════════════╗
║  🟩  CAMADA DE CATÁLOGO — Polaris (rede: spark-net + rust-net)                  ║
╠══════════════════════════════╪════════════════╪═════════════════════════════════╣
║                              │                │                                  ║
║   ┌──────────────────────────┴────────────────┴──────────────────────────────┐  ║
║   │                        Apache Polaris                                    │  ║
║   │                                                                          │  ║
║   │   REST API  → :8181       OAuth2 (client_credentials)                   │  ║
║   │   Health    → :8182       client_id:     root                           │  ║
║   │                           client_secret: s3cr3t                         │  ║
║   │                           scope: PRINCIPAL_ROLE:ALL                     │  ║
║   │                                                                          │  ║
║   │   📂 poc_catalog (INTERNAL)                                              │  ║
║   │       └── cepel/           ← namespace                                  │  ║
║   │           └── tabelas...   ← gerenciadas via REST                       │  ║
║   │                                                                          │  ║
║   │   ⚙️  SKIP_CREDENTIAL_SUBSCOPING_INDIRECTION: true                       │  ║
║   │      (desativa AWS STS — necessário para RustFS)                        │  ║
║   └──────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
                              ▲
                              │  REST API (Iceberg SDK v2)
                              │  iceberg-aws-bundle-1.5.2.jar
                              │  iceberg-spark-runtime-3.5_2.12-1.5.2.jar
╔══════════════════════════════╪═════════════════════════════════════════════════╗
║  🟦  CAMADA DE PROCESSAMENTO — Spark (rede: spark-net)                         ║
╠══════════════════════════════╪═════════════════════════════════════════════════╣
║                              │                                                  ║
║   ┌───────────────────────────┴──────────────────────────────────────────────┐  ║
║   │                       Spark Master  :8088 / :7077                       │  ║
║   │                       imagem: spark-master:dev                          │  ║
║   └──────────────────────────────────────────────────────────────────────────┘  ║
║              ▲                                        ▲                          ║
║              │  spark://spark-master:7077             │                          ║
║   ┌──────────┴────────────┐             ┌─────────────┴──────────────┐          ║
║   │    Spark Worker 1     │             │     Spark Worker 2         │          ║
║   │    :8081              │             │     :8082                  │          ║
║   │    imagem: spark:dev  │             │     imagem: spark:dev      │          ║
║   └───────────────────────┘             └────────────────────────────┘          ║
║                                                                                  ║
║   ⚙️  spark-defaults.conf                                                        ║
║      spark.sql.catalog.polaris.type          = rest                             ║
║      spark.sql.catalog.polaris.uri           = http://polaris:8181/api/catalog  ║
║      spark.sql.catalog.polaris.credential    = root:s3cr3t                      ║
║      spark.sql.catalog.polaris.io-impl       = S3FileIO                         ║
║      spark.sql.catalog.polaris.s3.endpoint   = http://rustfs:9000               ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
                              ▲
                              │  PySpark + Iceberg
╔══════════════════════════════╪═════════════════════════════════════════════════╗
║  🟨  CAMADA DE NOTEBOOK — Jupyter (rede: spark-net)                            ║
╠══════════════════════════════╪═════════════════════════════════════════════════╣
║                              │                                                  ║
║   ┌───────────────────────────┴──────────────────────────────────────────────┐  ║
║   │                        Jupyter Notebook  :8888                          │  ║
║   │                        imagem: jupyter:dev                              │  ║
║   │                                                                          │  ║
║   │   from pyspark.sql import SparkSession                                  │  ║
║   │   df.write.format("iceberg").saveAsTable("polaris.cepel.tabela")        │  ║
║   │   df = spark.read.format("iceberg").load("polaris.cepel.tabela")        │  ║
║   └──────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
                              ▲
                              │  ingestão (token Polaris + JWT bot)
                              │  openmetadata/ingestion:1.6.6
╔══════════════════════════════╪═════════════════════════════════════════════════╗
║  🟪  CAMADA DE GOVERNANÇA — OpenMetadata (rede: spark-net + rust-net)          ║
╠══════════════════════════════╪═════════════════════════════════════════════════╣
║                              │                                                  ║
║   ┌───────────────────────────┴──────────────────────────────────────────────┐  ║
║   │                   OpenMetadata Server  :8585 / :8586                    │  ║
║   │                   imagem: openmetadata/server:1.6.6                     │  ║
║   │                                                                          │  ║
║   │   admin@open-metadata.org  /  admin                                     │  ║
║   │   FERNET_KEY: jJgVqL9KpHx8t4YzW2mNcR5sA7bDfG1kU3oX6eQ0vBw=            │  ║
║   └──────────────────────────────────────────────────────────────────────────┘  ║
║              ▲                                        ▲                          ║
║              │  SQL (PostgreSQL driver)               │  HTTP REST               ║
║   ┌──────────┴────────────┐             ┌─────────────┴──────────────┐          ║
║   │     PostgreSQL        │             │      Elasticsearch         │          ║
║   │     :5432             │             │      :9201                 │          ║
║   │     postgres:14-alpine│             │      elasticsearch:8.15.0  │          ║
║   │                       │             │                            │          ║
║   │   db: openmetadata_db │             │   índices de busca         │          ║
║   │   user: om_user       │             │   xpack.security: false    │          ║
║   │   pass: om_user_pass  │             │   ES_JAVA_OPTS: -Xmx1g     │          ║
║   └───────────────────────┘             └────────────────────────────┘          ║
║                                                                                  ║
║   🔄 migrate (roda 1x só)                                                        ║
║      openmetadata-migrate → cria 100+ tabelas no PostgreSQL → morre             ║
║      depends_on: postgres (healthy) → server só sobe após migrate terminar      ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════════╗
║                          🔄  FLUXO COMPLETO DE DADOS                            ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║  Jupyter (PySpark)                                                               ║
║      │                                                                           ║
║      ├──► Spark Master/Workers  ──► processa os dados                           ║
║      │                                                                           ║
║      ├──► Polaris (REST)        ──► registra metadados da tabela Iceberg        ║
║      │        │                                                                  ║
║      │        └──► RustFS (S3)  ──► salva arquivos .parquet + metadata          ║
║      │                                                                           ║
║      └──► OpenMetadata          ──► ingestão via token Polaris + JWT bot        ║
║               │                       descobre tabelas, schema, linhagem        ║
║               ├──► PostgreSQL   ──► persiste metadados                          ║
║               └──► Elasticsearch──► indexa para busca                           ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════════╗
║                        🌐  REFERÊNCIA RÁPIDA DE ACESSOS                         ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║   Serviço            URL                        Credenciais                      ║
║   ─────────────────  ───────────────────────    ──────────────────────────────  ║
║   Spark Master UI    http://localhost:8088       —                               ║
║   Spark Worker 1     http://localhost:8081       —                               ║
║   Spark Worker 2     http://localhost:8082       —                               ║
║   Jupyter            http://localhost:8888       ver docker-compose.yml          ║
║   OpenMetadata       http://localhost:8585       admin / admin                   ║
║   Polaris            http://localhost:8181       root / s3cr3t                   ║
║   Elasticsearch      http://localhost:9201       —                               ║
║   S3Browser          http://localhost:9090       ver docker-compose.yml          ║
║   RustFS S3 API      http://localhost:9000       rustfs / rustfs123              ║
║   RustFS Console     http://localhost:9001       rustfs / rustfs123              ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════════╗
║                        📋  ORDEM DE SUBIDA DOS SERVIÇOS                         ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║   1️⃣  Criar rede rust-net (subnet 192.168.100.0/24)                              ║
║       └── docker network create --subnet=192.168.100.0/24                       ║
║               --gateway=192.168.100.1 rust-net                                  ║
║                                                                                  ║
║   2️⃣  Subir RustFS                                                               ║
║       └── cd services/rustfs && docker compose up -d                            ║
║                                                                                  ║
║   3️⃣  Criar bucket bronze no S3Browser (http://localhost:9090)                   ║
║                                                                                  ║
║   4️⃣  Build das imagens locais                                                   ║
║       ├── docker build -t spark-master:dev ./services/spark/spark/               ║
║       └── docker build -t jupyter:dev ./services/jupyter/                        ║
║                                                                                  ║
║   5️⃣  Subir stack principal                                                      ║
║       └── docker compose up -d                                                   ║
║                                                                                  ║
║   6️⃣  Configurar Polaris (catalog + namespace)                                   ║
║       └── chmod +x setup_polaris.sh && ./setup_polaris.sh                       ║
║                                                                                  ║
║   7️⃣  Copiar JARs Iceberg para os containers                                     ║
║       └── chmod +x copy_jars.sh && ./copy_jars.sh                               ║
║                                                                                  ║
║   8️⃣  Acessar Jupyter e rodar script de teste                                    ║
║       └── http://localhost:8888                                                  ║
║                                                                                  ║
║   9️⃣  Inicializar OpenMetadata                                                   ║
║       └── chmod +x start.sh && ./start.sh                                       ║
║       └── sudo docker exec openmetadata-server                                   ║
║               /opt/openmetadata/bootstrap/openmetadata-ops.sh reindex           ║
║                                                                                  ║
║   🔟  Ingestão Polaris → OpenMetadata                                            ║
║       ├── Gerar token Polaris                                                    ║
║       ├── Atualizar JWT ingestion-bot no iceberg-polaris.yaml                   ║
║       └── sudo docker run ... openmetadata/ingestion:1.6.6 /tmp/run_ingest.py  ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```
