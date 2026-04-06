# 🐳 Spark + Hadoop + Jupyter — Ambiente Docker

> Documentação do cluster local com Apache Spark, HDFS e JupyterLab rodando via Docker Compose.

---

## 📁 Estrutura Geral

```
spark-docker/
├── spark/
│   └── Dockerfile          # Imagem do Spark Master e Workers
├── hadoop/
│   └── Dockerfile          # Imagem do HDFS NameNode e DataNode
├── jupyter/
│   └── Dockerfile          # Imagem do JupyterLab com PySpark
└── docker-compose.yml      # Orquestração de todos os serviços
```

---

## 🏗️ Arquitetura do Cluster

```
┌──────────────────────────────────────────────────────┐
│                    spark-net                          │
│                                                      │
│  Jupyter ──────────────────▶ Spark Master (:7077)    │
│  (:8888)                        │                    │
│                           ┌─────┴─────┐              │
│                           ▼           ▼              │
│                     Worker 1     Worker 2            │
│                     (:8081)      (:8081)             │
│                                                      │
│  HDFS DataNode ◀──────────▶ HDFS NameNode (:8020)   │
│  (:9864)                      (:9870)                │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## 🌐 Portas e Mapeamentos

### Portas internas dos containers

| Container        | Porta | Protocolo  | Função                                          |
|------------------|-------|------------|-------------------------------------------------|
| spark-master     | 7077  | Spark RPC  | Workers e clientes enviam/recebem jobs          |
| spark-master     | 8080  | HTTP       | UI web do Master                                |
| spark-worker-1   | 8081  | HTTP       | UI web do Worker 1                              |
| spark-worker-2   | 8081  | HTTP       | UI web do Worker 2                              |
| jupyter          | 8888  | HTTP       | Interface JupyterLab                            |
| hdfs-namenode    | 8020  | Hadoop RPC | DataNodes e clientes HDFS se conectam           |
| hdfs-namenode    | 9870  | HTTP       | UI web do NameNode                              |
| hdfs-datanode    | 9864  | HTTP       | UI web do DataNode                              |

### Mapeamento Container → Host (formato `"HOST:CONTAINER"` no compose)

| Container        | Porta no Container | Porta no Host | No docker-compose.yml |
|------------------|--------------------|---------------|-----------------------|
| spark-master     | 8080               | 8080          | `"8080:8080"`         |
| spark-master     | 7077               | 7077          | `"7077:7077"`         |
| spark-worker-1   | 8081               | 8081          | `"8081:8081"`         |
| spark-worker-2   | 8081               | **8082**      | `"8082:8081"`         |
| jupyter          | 8888               | 8888          | `"8888:8888"`         |
| hdfs-namenode    | 9870               | 9870          | `"9870:9870"`         |
| hdfs-namenode    | 8020               | 8020          | `"8020:8020"`         |
| hdfs-datanode    | 9864               | 9864          | `"9864:9864"`         |

> **Por que o Worker 2 usa porta 8082 no host?**
> O processo do Worker sempre roda na porta 8081 dentro do container.
> Como o Worker 1 já ocupa a porta 8081 no host, o Worker 2 é mapeado para 8082.
> `Browser → localhost:8082 → Docker → container → porta 8081`

---

## 🔗 Conexões Internas (rede `spark-net`)

```
Jupyter          →  spark-master:7077     (envia jobs PySpark)
spark-worker-1   →  spark-master:7077     (se registra, recebe tarefas)
spark-worker-2   →  spark-master:7077     (se registra, recebe tarefas)
hdfs-datanode    →  hdfs-namenode:8020    (se registra, reporta blocos)
```

---

## 🌍 URLs para acesso no Browser

| Serviço           | URL                                        |
|-------------------|--------------------------------------------|
| Spark Master UI   | http://localhost:8080                      |
| Spark Worker 1 UI | http://localhost:8081                      |
| Spark Worker 2 UI | http://localhost:8082                      |
| JupyterLab        | http://localhost:8888?token=spark123       |
| HDFS NameNode UI  | http://localhost:9870                      |
| HDFS DataNode UI  | http://localhost:9864                      |

---

## ⚙️ Dockerfiles — Problemas e Soluções

### 🔶 Spark (`spark/Dockerfile`)

**Problema:** O download do binário do Spark com `-q` (quiet) silencia erros, dificultando diagnóstico.

```dockerfile
# ❌ Com -q: erros ficam ocultos — difícil de depurar
RUN wget -q https://...

# ✅ Alternativa mais segura para depuração:
RUN wget https://...
```

**Versões a verificar:**
- Conferir a versão do Spark (`SPARK_VERSION`) está correta e disponível no mirror
- Testar o link de download antes de rodar o build
- Às vezes é necessário fazer login no Docker Hub para acessar algumas imagens base

**Abordagens testadas para download:**

```dockerfile
# Opção 1: curl com pipe direto
RUN curl -fsSL https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    | tar -xz -C /opt && mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME}

# Opção 2: wget com extração manual (mais explícita)
RUN wget https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    && tar xf spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    && mv spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME} \
    && rm spark-${SPARK_VERSION}-bin-hadoop3.tgz
```

> **Nota sobre Alpine (musl) vs glibc:**
> O Spark usa libs nativas (ex: Snappy para compressão Parquet) compiladas para glibc.
> Se a imagem base for Alpine (musl), adicione `gcompat` no `apk add`.

---

### 🔷 Hadoop (`hadoop/Dockerfile`)

**Dockerfile final recomendado:**

```dockerfile
FROM eclipse-temurin:17-jre-alpine

# gcompat: necessário porque libhadoop.so foi compilada para glibc (não musl/Alpine)
RUN apk add --no-cache bash wget procps tini gcompat

ENV HADOOP_VERSION=3.3.6
ENV HADOOP_HOME=/opt/hadoop
ENV PATH="${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${PATH}"
ENV HDFS_NAMENODE_USER=root
ENV HDFS_DATANODE_USER=root

RUN wget -q https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz \
    && tar xf hadoop-${HADOOP_VERSION}.tar.gz \
    && mv hadoop-${HADOOP_VERSION} ${HADOOP_HOME} \
    && rm hadoop-${HADOOP_VERSION}.tar.gz

# Desabilita libs nativas para evitar SIGSEGV (segfault) no DataNode em Alpine
# Também adiciona flags de módulos Java 17 para compatibilidade com JAXB/WebHDFS
RUN printf 'export JAVA_HOME=${JAVA_HOME}\n\
export HADOOP_OPTS="${HADOOP_OPTS} -Djava.library.path="\n\
export HADOOP_NAMENODE_OPTS="${HADOOP_NAMENODE_OPTS} --add-opens java.base/java.lang=ALL-UNNAMED"\n\
export HADOOP_DATANODE_OPTS="${HADOOP_DATANODE_OPTS} --add-opens java.base/java.lang=ALL-UNNAMED"\n\
export HADOOP_OPTIONAL_TOOLS=""\n' >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

# Remove as libs nativas para garantir que não sejam carregadas
RUN rm -f ${HADOOP_HOME}/lib/native/*

# core-site.xml: define o endereço do NameNode
RUN printf '<?xml version="1.0"?>\n\
<configuration>\n\
  <property>\n\
    <name>fs.defaultFS</name>\n\
    <value>hdfs://hdfs-namenode:8020</value>\n\
  </property>\n\
</configuration>\n' > ${HADOOP_HOME}/etc/hadoop/core-site.xml

# hdfs-site.xml: desabilita verificação de permissões (ok para desenvolvimento local)
RUN printf '<?xml version="1.0"?>\n\
<configuration>\n\
  <property>\n\
    <name>dfs.permissions.enabled</name>\n\
    <value>false</value>\n\
  </property>\n\
</configuration>\n' > ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml

WORKDIR ${HADOOP_HOME}
ENTRYPOINT ["tini", "--"]
```

**Problemas resolvidos:**

| Problema                          | Causa                                         | Solução                                                |
|-----------------------------------|-----------------------------------------------|--------------------------------------------------------|
| DataNode crasha com SIGSEGV       | `libhadoop.so` usa glibc, imagem usa musl     | Adicionar `gcompat`; remover libs nativas              |
| `NoClassDefFoundError` no JAXB    | Java 17 não carrega JAXB sem flags extras      | `--add-opens java.base/java.lang=ALL-UNNAMED`          |
| Permissão negada no HDFS          | DataNode pertence ao root, Jupyter roda como jovyan | `dfs.permissions.enabled=false` no hdfs-site.xml |
| `HADOOP_OPTS` ignorado pelo DataNode | Variável de ambiente não propagada corretamente | Definir diretamente no `hadoop-env.sh`              |

---

### 🟢 Jupyter (`jupyter/Dockerfile`)

**Problema: Java ausente**

A abordagem de copiar o Java de outra imagem com `COPY --from` não funciona se a imagem de origem não tiver Java no caminho esperado:

```dockerfile
# ❌ Não funciona — eclipse-temurin:17-jre-alpine não expõe /opt/java
COPY --from=eclipse-temurin:17-jre-alpine /opt/java /opt/java
```

**Solução: instalar Java diretamente via apt:**

```dockerfile
# ✅ Instala Java via apt — necessário para SparkSession funcionar
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl tini procps default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"
```

> ⚠️ **Importante:** O caminho do `JAVA_HOME` deve estar correto.
> Sem isso, a `SparkSession` falha ao iniciar — o PySpark não consegue localizar a JVM.

> **Por que Jupyter não precisa de `gcompat`?**
> A imagem base do Jupyter é Debian, que já usa glibc nativamente.
> `gcompat` só é necessário em Alpine (que usa musl).

---

## 📊 Resumo: `gcompat` por imagem

| Imagem                        | Precisa de `gcompat`? | Motivo                                      |
|-------------------------------|----------------------|---------------------------------------------|
| spark (Workers/Master)        | ✅ Sim               | Snappy (compressão Parquet) usa glibc       |
| hadoop (NameNode + DataNode)  | ✅ Sim               | `libhadoop.so` usa glibc                    |
| jupyter                       | ❌ Não               | Base Debian já tem glibc                    |

---

## ⚠️ Limitação Conhecida: HDFS WebUI no Docker

### O "Browse Directory" não consegue abrir arquivos

Isso é uma **limitação arquitetural**, não um bug de configuração.

**Por quê acontece:**
1. O NameNode faz um **HTTP redirect** para o DataNode
2. Esse redirect usa **hostnames internos do container** (ex: `hdfs-datanode`)
3. O navegador no host **não consegue resolver esses hostnames internos**

**Solução:** Não existe via configuração simples. Exigiria que o Hadoop implementasse proxy em vez de redirect, ou modificação no código-fonte do HDFS.

### O que funciona e o que não funciona:

| Operação                                  | Status                    |
|-------------------------------------------|---------------------------|
| Gravar arquivos via Spark                 | ✅ Funciona               |
| Ler arquivos via Spark                    | ✅ Funciona               |
| Listar via terminal (`hdfs dfs -ls`)      | ✅ Funciona               |
| WebHDFS REST API (`?op=LISTSTATUS`)       | ✅ Funciona               |
| Navegar diretórios na UI web              | ✅ Funciona               |
| Ver **conteúdo** de arquivos na UI web    | ❌ Limitação no Docker    |

### Testando via WebHDFS REST API:

```bash
# Listar arquivos em um diretório
curl http://localhost:9870/webhdfs/v1/teste/ui/?op=LISTSTATUS
```

> Para **estudo e desenvolvimento**, o ambiente está completo.
> A limitação do WebUI é apenas cosmética — não afeta o uso real do HDFS.

---

## 🛠️ Comandos Úteis

```bash
# Subir o cluster
docker compose up -d

# Ver status de todos os containers
docker compose ps

# Ver logs de um container específico
docker compose logs spark-master
docker compose logs -f jupyter          # -f = acompanha em tempo real
docker compose logs hdfs-namenode
docker compose logs hdfs-datanode

# Parar todos os containers
docker compose down

# Parar e remover volumes (⚠️ dados serão perdidos)
docker compose down -v

# Entrar num container interativamente
docker exec -it jupyter bash
docker exec -it spark-master bash

# Reiniciar um container específico
docker compose restart spark-worker-1

# Build de uma imagem específica (ex: durante desenvolvimento)
docker build -t testing .
docker build -t jupyter .
```

---

## 📝 Notas Adicionais

- O flag `-q` no `wget` silencia a saída — útil em produção, mas **evite durante depuração** pois esconde erros
- Sempre verifique a versão do Spark/Hadoop disponível no mirror antes de definir `SPARK_VERSION` / `HADOOP_VERSION`
- O token padrão do JupyterLab no ambiente é `spark123` (configurável no docker-compose.yml)














asus@asus-VivoBook-S14-X430UN:~/Desktop/spark-docker/alarik$ docker network ls | grep spark
da8049f3e6f2   spark-docker_spark-net   bridge    local


asus@asus-VivoBook-S14-X430UN:~/Desktop/spark-docker/alarik$ docker exec jupyter curl -s http://alarik:8080/health
OCI runtime exec failed: exec failed: unable to start container process: exec: "curl": executable file not found in $PATH


docker exec -it jupyter bash









Documentacao: Spark + Alarik (S3-compatible) - Problemas e Solucoes
Ambiente
Spark: 3.5.8 (cluster Docker: spark-master, spark-worker-1, spark-worker-2)
Jupyter: container separado (driver PySpark)
Alarik: object storage S3-compatible (ghcr.io/achtungsoftware/alarik)
Hadoop: 3.3.4
Problema 1: UnknownHostException - bronze.alarik
Erro: java.net.UnknownHostException: bronze.alarik

Causa: O AWS SDK usa virtual-hosted-style URLs por padrao, transformando o bucket em subdominio: http://bronze.alarik:8085. Como nao existe DNS para bronze.alarik, falha.

Solucao: Forcar path-style access no builder da SparkSession:

python
.config("spark.hadoop.fs.s3a.path.style.access", "true")
Isso muda as requests de http://bronze.alarik:8085/key para http://alarik:8085/bronze/key.

Importante: A config deve estar no builder da SparkSession, nao via spark.conf.set(), pois o S3AFileSystem cacheia na primeira chamada.

Problema 2: Connection Refused na porta 8085
Erro: Connect to alarik:8085 [alarik/172.18.0.3] failed: Connection refused

Causa: O container Alarik mapeia 8085->8080 (externo->interno). Dentro da rede Docker, os containers se comunicam pela porta interna (8080).

Solucao:

python
.config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080")
A porta 8085 so funciona de fora do Docker (localhost:8085).

Problema 3: 403 Forbidden
Erro: AmazonS3Exception: Forbidden (Status Code: 403)

Causa: Credenciais incorretas (placeholder "SUA_SECRET_KEY" em vez da chave real).

Solucao: Usar as credenciais corretas no builder:

python
.config("spark.hadoop.fs.s3a.access.key", "DANLQMEACSNA6BQMHSPV")
.config("spark.hadoop.fs.s3a.secret.key", "iCj2+E7qMODIpuw7xGrxHCEGlpRbVPjz7AWVW06g")
Problema 4: _temporary - Could not rename
Erro: java.io.IOException: Could not rename s3a://bronze/test_debug/_temporary/...

Causa: O FileOutputCommitter padrao do Spark usa rename de diretorios, que nao funciona em object stores S3-compatible (Alarik nao suporta rename atomico).

Solucao: Usar o S3A committer (magic ou directory) que elimina a necessidade de rename.

Problema 5: ClassNotFoundException - PathOutputCommitProtocol
Erro: java.lang.ClassNotFoundException: org.apache.spark.internal.io.cloud.PathOutputCommitProtocol

Causa: O JAR spark-hadoop-cloud nao estava instalado.

Solucao: Instalar o JAR em todos os containers (master, workers E jupyter):

bash
wget -O /tmp/spark-hadoop-cloud_2.12-3.5.5.jar https://repo1.maven.org/maven2/org/apache/spark/spark-hadoop-cloud_2.12/3.5.5/spark-hadoop-cloud_2.12-3.5.5.jar

docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-master:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-1:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-2:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar jupyter:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar jupyter:/usr/local/lib/python3.12/site-packages/pyspark/jars/

docker restart spark-master spark-worker-1 spark-worker-2 jupyter
Importante: Apos instalar o JAR, reiniciar o kernel do Jupyter para recarregar a JVM.

Problema 6: FileAlreadyExistsException - "since it is a file"
Erro: FileAlreadyExistsException: Can't make directory for path 's3a://bronze/...' since it is a file

Causa: O Alarik retorna 200 OK com metadata no HEAD para qualquer path, fazendo o S3AFileSystem pensar que o path ja existe como arquivo. O magic committer tenta mkdirs que falha.

Solucao: Usar o directory committer em vez do magic:

python
.config("spark.hadoop.fs.s3a.committer.name", "directory")
.config("spark.hadoop.fs.s3a.committer.staging.tmp.path", "/tmp/spark-staging")
Problema 7: algorithm.version=2 tambem falha (NoSuchKey/CopyObject)
Erro: AmazonS3Exception: The specified key does not exist (NoSuchKey) durante copyFile

Causa: O algorithm.version=2 ainda usa CopyObject internamente, que o Alarik nao implementa corretamente.

Solucao: Nao usar algorithm.version=2 com Alarik. Usar os S3A committers (directory ou magic).

Configuracao Final Funcional
python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Salvar no Alarik") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.access.key", "DANLQMEACSNA6BQMHSPV") \
    .config("spark.hadoop.fs.s3a.secret.key", "SUA_SECRET_KEY") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.bucket.probe", "0") \
    .config("spark.sql.sources.commitProtocolClass",
            "org.apache.spark.internal.io.cloud.PathOutputCommitProtocol") \
    .config("spark.hadoop.mapreduce.outputcommitter.factory.scheme.s3a",
            "org.apache.hadoop.fs.s3a.commit.S3ACommitterFactory") \
    .config("spark.hadoop.fs.s3a.committer.name", "directory") \
    .config("spark.hadoop.fs.s3a.committer.staging.tmp.path", "/tmp/spark-staging") \
    .getOrCreate()
Resumo das Configs Obrigatorias para Alarik
Config	Valor	Motivo
fs.s3a.endpoint	http://alarik:8080	Porta interna Docker
fs.s3a.path.style.access	true	Evita virtual-hosted DNS
fs.s3a.connection.ssl.enabled	false	HTTP sem TLS
fs.s3a.bucket.probe	0	Evita checagem de bucket
fs.s3a.committer.name	directory	Evita rename/mkdirs
commitProtocolClass	PathOutputCommitProtocol	Habilita S3A committers
outputcommitter.factory.scheme.s3a	S3ACommitterFactory	Factory do committer
JAR Necessario
spark-hadoop-cloud_2.12-3.5.5.jar — deve estar em:






/opt/spark/jars/ (todos os containers Spark)
/usr/local/lib/python3.12/site-packages/pyspark/jars/ (container Jupyter)























Documentacao: Spark + Alarik (S3-compatible) - Problemas e Solucoes
Ambiente
Spark: 3.5.8 (cluster Docker: spark-master, spark-worker-1, spark-worker-2)
Jupyter: container separado (driver PySpark)
Alarik: object storage S3-compatible (ghcr.io/achtungsoftware/alarik)
Hadoop: 3.3.4
Problema 1: UnknownHostException - bronze.alarik
Erro: java.net.UnknownHostException: bronze.alarik

Causa: O AWS SDK usa virtual-hosted-style URLs por padrao, transformando o bucket em subdominio: http://bronze.alarik:8085. Como nao existe DNS para bronze.alarik, falha.

Solucao: Forcar path-style access no builder da SparkSession:

python
.config("spark.hadoop.fs.s3a.path.style.access", "true")
Isso muda as requests de http://bronze.alarik:8085/key para http://alarik:8085/bronze/key.

Importante: A config deve estar no builder da SparkSession, nao via spark.conf.set(), pois o S3AFileSystem cacheia na primeira chamada.

Problema 2: Connection Refused na porta 8085
Erro: Connect to alarik:8085 [alarik/172.18.0.3] failed: Connection refused

Causa: O container Alarik mapeia 8085->8080 (externo->interno). Dentro da rede Docker, os containers se comunicam pela porta interna (8080).

Solucao:

python
.config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080")
A porta 8085 so funciona de fora do Docker (localhost:8085).

Problema 3: 403 Forbidden
Erro: AmazonS3Exception: Forbidden (Status Code: 403)

Causa: Credenciais incorretas (placeholder "SUA_SECRET_KEY" em vez da chave real).

Solucao: Usar as credenciais corretas no builder:

python
.config("spark.hadoop.fs.s3a.access.key", "DANLQMEACSNA6BQMHSPV")
.config("spark.hadoop.fs.s3a.secret.key", "iCj2+E7qMODIpuw7xGrxHCEGlpRbVPjz7AWVW06g")
Problema 4: _temporary - Could not rename
Erro: java.io.IOException: Could not rename s3a://bronze/test_debug/_temporary/...

Causa: O FileOutputCommitter padrao do Spark usa rename de diretorios, que nao funciona em object stores S3-compatible (Alarik nao suporta rename atomico).

Solucao: Usar o S3A committer (magic ou directory) que elimina a necessidade de rename.

Problema 5: ClassNotFoundException - PathOutputCommitProtocol
Erro: java.lang.ClassNotFoundException: org.apache.spark.internal.io.cloud.PathOutputCommitProtocol

Causa: O JAR spark-hadoop-cloud nao estava instalado.

Solucao: Instalar o JAR em todos os containers (master, workers E jupyter):

bash
wget -O /tmp/spark-hadoop-cloud_2.12-3.5.5.jar https://repo1.maven.org/maven2/org/apache/spark/spark-hadoop-cloud_2.12/3.5.5/spark-hadoop-cloud_2.12-3.5.5.jar

docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-master:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-1:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-2:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar jupyter:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar jupyter:/usr/local/lib/python3.12/site-packages/pyspark/jars/

docker restart spark-master spark-worker-1 spark-worker-2 jupyter
Importante: Apos instalar o JAR, reiniciar o kernel do Jupyter para recarregar a JVM.

Problema 6: FileAlreadyExistsException - "since it is a file"
Erro: FileAlreadyExistsException: Can't make directory for path 's3a://bronze/...' since it is a file

Causa: O Alarik retorna 200 OK com metadata no HEAD para qualquer path, fazendo o S3AFileSystem pensar que o path ja existe como arquivo. O magic committer tenta mkdirs que falha.

Solucao: Usar o directory committer em vez do magic:

python
.config("spark.hadoop.fs.s3a.committer.name", "directory")
.config("spark.hadoop.fs.s3a.committer.staging.tmp.path", "/tmp/spark-staging")
Problema 7: algorithm.version=2 tambem falha (NoSuchKey/CopyObject)
Erro: AmazonS3Exception: The specified key does not exist (NoSuchKey) durante copyFile

Causa: O algorithm.version=2 ainda usa CopyObject internamente, que o Alarik nao implementa corretamente.

Solucao: Nao usar algorithm.version=2 com Alarik. Usar os S3A committers (directory ou magic).

Configuracao Final Funcional
python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Salvar no Alarik") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.access.key", "DANLQMEACSNA6BQMHSPV") \
    .config("spark.hadoop.fs.s3a.secret.key", "SUA_SECRET_KEY") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.bucket.probe", "0") \
    .config("spark.sql.sources.commitProtocolClass",
            "org.apache.spark.internal.io.cloud.PathOutputCommitProtocol") \
    .config("spark.hadoop.mapreduce.outputcommitter.factory.scheme.s3a",
            "org.apache.hadoop.fs.s3a.commit.S3ACommitterFactory") \
    .config("spark.hadoop.fs.s3a.committer.name", "directory") \
    .config("spark.hadoop.fs.s3a.committer.staging.tmp.path", "/tmp/spark-staging") \
    .getOrCreate()
Resumo das Configs Obrigatorias para Alarik
Config	Valor	Motivo
fs.s3a.endpoint	http://alarik:8080	Porta interna Docker
fs.s3a.path.style.access	true	Evita virtual-hosted DNS
fs.s3a.connection.ssl.enabled	false	HTTP sem TLS
fs.s3a.bucket.probe	0	Evita checagem de bucket
fs.s3a.committer.name	directory	Evita rename/mkdirs
commitProtocolClass	PathOutputCommitProtocol	Habilita S3A committers
outputcommitter.factory.scheme.s3a	S3ACommitterFactory	Factory do committer
JAR Necessario
spark-hadoop-cloud_2.12-3.5.5.jar — deve estar em:

/opt/spark/jars/ (todos os containers Spark)
/usr/local/lib/python3.12/site-packages/pyspark/jars/ (container Jupyter)
mesmo assim nao esta funcionando

Dado que o Alarik tem limitacoes significativas na compatibilidade S3 (nao suporta rename, CopyObject, mkdirs, e bulk delete retorna 404), a abordagem mais confiavel e escrever localmente e fazer upload via boto3:

python
import boto3
import os

data = [("Alice", 30), ("Bob", 25)]
columns = ["name", "age"]
df = spark.createDataFrame(data, columns)

df.write.mode("overwrite").parquet("/tmp/alarik_output/")

s3 = boto3.client(
    "s3",
    endpoint_url="http://alarik:8080",
    aws_access_key_id="DANLQMEACSNA6BQMHSPV",
    aws_secret_access_key="iCj2+E7qMODIpuw7xGrxHCEGlpRbVPjz7AWVW06g",
)

for root, dirs, files in os.walk("/tmp/alarik_output"):
    for f in files:
        local = os.path.join(root, f)
        key = "test_final/" + os.path.relpath(local, "/tmp/alarik_output")
        s3.upload_file(local, "bronze", key)
        print(f"Uploaded: {key}")

print("Sucesso!")
Isso contorna todos os problemas do Alarik. Para produção, encapsule isso numa funcao helper. A conclusao e que o Alarik nao e compativel o suficiente com a API S3 para funcionar com os committers nativos do Spark (nem FileOutputCommitter, nem S3A magic/directory). A abordagem boto3 e a mais estavel.

sim pls

Adicionei o Problema 8 a documentacao:

Problema 8: Directory Committer trava no Stage 0
Sintoma: Execucao fica parada em [Stage 0:> (0 + 2) / 2] indefinidamente

Causa: O directory committer depende de CompleteMultipartUpload na fase de commit, que o Alarik nao implementa corretamente ou tem timeout muito alto.

Solucao (workaround): Escrever localmente via Spark e fazer upload via boto3:

python
import boto3
import os

df.write.mode("overwrite").parquet("/tmp/alarik_output/")

s3 = boto3.client(
    "s3",
    endpoint_url="http://alarik:8080",
    aws_access_key_id="DANLQMEACSNA6BQMHSPV",
    aws_secret_access_key="SUA_SECRET_KEY",
)

for root, dirs, files in os.walk("/tmp/alarik_output"):
    for f in files:
        local = os.path.join(root, f)
        key = "destino/" + os.path.relpath(local, "/tmp/alarik_output")
        s3.upload_file(local, "bronze", key)
Conclusao Final
O Alarik nao e compativel com os committers nativos do Spark (FileOutputCommitter, S3A magic, S3A directory). As APIs S3 que faltam ou estao quebradas:

Rename/CopyObject: nao funciona
Bulk Delete: retorna 404
HEAD para paths inexistentes: retorna 200 (faz S3AFileSystem pensar que existe arquivo)
mkdirs: falha por causa do HEAD incorreto
CompleteMultipartUpload: trava ou nao completa
Recomendacao: Para escrita confiavel no Alarik via Spark, use a abordagem local + boto3 upload. Para leitura, o S3A funciona normalmente com path.style.access=true e porta 8080.

sim pls

Aqui esta a documentacao completa atualizada:

Documentacao: Spark + Alarik (S3-compatible) - Problemas e Solucoes
Ambiente
Spark: 3.5.8 (cluster Docker: spark-master, spark-worker-1, spark-worker-2)
Jupyter: container separado (driver PySpark)
Alarik: object storage S3-compatible (ghcr.io/achtungsoftware/alarik)
Hadoop: 3.3.4
Problema 1: UnknownHostException - bronze.alarik
Erro: java.net.UnknownHostException: bronze.alarik

Causa: O AWS SDK usa virtual-hosted-style URLs por padrao, transformando o bucket em subdominio: http://bronze.alarik:8085. Como nao existe DNS para bronze.alarik, falha.

Solucao: Forcar path-style access no builder da SparkSession:

python
.config("spark.hadoop.fs.s3a.path.style.access", "true")
Isso muda as requests de http://bronze.alarik:8085/key para http://alarik:8085/bronze/key.

Importante: A config deve estar no builder da SparkSession, nao via spark.conf.set(), pois o S3AFileSystem cacheia na primeira chamada.

Problema 2: Connection Refused na porta 8085
Erro: Connect to alarik:8085 [alarik/172.18.0.3] failed: Connection refused

Causa: O container Alarik mapeia 8085->8080 (externo->interno). Dentro da rede Docker, os containers se comunicam pela porta interna (8080).

Solucao:

python
.config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080")
A porta 8085 so funciona de fora do Docker (localhost:8085).

Problema 3: 403 Forbidden
Erro: AmazonS3Exception: Forbidden (Status Code: 403)

Causa: Credenciais incorretas (placeholder "SUA_SECRET_KEY" em vez da chave real).

Solucao: Usar as credenciais corretas no builder:

python
.config("spark.hadoop.fs.s3a.access.key", "SUA_ACCESS_KEY")
.config("spark.hadoop.fs.s3a.secret.key", "SUA_SECRET_KEY_REAL")
Problema 4: _temporary - Could not rename
Erro: java.io.IOException: Could not rename s3a://bronze/test_debug/_temporary/...

Causa: O FileOutputCommitter padrao do Spark usa rename de diretorios, que nao funciona em object stores S3-compatible (Alarik nao suporta rename atomico).

Solucao tentada: Usar o S3A committer (magic ou directory) que elimina a necessidade de rename. Requer o JAR spark-hadoop-cloud.

Problema 5: ClassNotFoundException - PathOutputCommitProtocol
Erro: java.lang.ClassNotFoundException: org.apache.spark.internal.io.cloud.PathOutputCommitProtocol

Causa: O JAR spark-hadoop-cloud nao estava instalado.

Solucao: Instalar o JAR em todos os containers (master, workers E jupyter):

bash
wget -O /tmp/spark-hadoop-cloud_2.12-3.5.5.jar \
  https://repo1.maven.org/maven2/org/apache/spark/spark-hadoop-cloud_2.12/3.5.5/spark-hadoop-cloud_2.12-3.5.5.jar

docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-master:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-1:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-2:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar jupyter:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar \
  jupyter:/usr/local/lib/python3.12/site-packages/pyspark/jars/

docker restart spark-master spark-worker-1 spark-worker-2 jupyter
Importante: Apos instalar o JAR, reiniciar o kernel do Jupyter para recarregar a JVM.

Problema 6: FileAlreadyExistsException (Magic Committer)
Erro: FileAlreadyExistsException: Can't make directory for path 's3a://bronze/...' since it is a file

Causa: O Alarik retorna 200 OK com metadata no HEAD para qualquer path (mesmo inexistente), fazendo o S3AFileSystem pensar que o path ja existe como arquivo. O magic committer tenta mkdirs que falha.

Solucao tentada: Usar o directory committer em vez do magic e bucket.probe=0:

python
.config("spark.hadoop.fs.s3a.bucket.probe", "0")
.config("spark.hadoop.fs.s3a.committer.name", "directory")
Problema 7: algorithm.version=2 falha com rename
Erro: java.io.IOException: Could not rename (mesmo com algorithm v2)

Causa: O algorithm.version=2 reduz o numero de renames mas ainda usa rename internamente, que o Alarik nao suporta.

Solucao: Nao usar algorithm.version=2 com Alarik. Os S3A committers sao necessarios.

Problema 8: Directory Committer trava no Stage 0
Sintoma: Execucao fica parada em [Stage 0:> (0 + 2) / 2] indefinidamente.

Causa: O directory committer depende de CompleteMultipartUpload na fase de commit, que o Alarik nao implementa corretamente ou tem timeout muito alto.

Solucao: Nenhum committer nativo do Spark funciona com Alarik. Usar abordagem local + boto3 (ver Solucao Final).

Solucao Final: Escrita Local + Upload via boto3
Como o Alarik nao suporta as APIs S3 necessarias para os committers do Spark, a abordagem mais confiavel e:

python
import boto3
import os

df.write.mode("overwrite").parquet("/tmp/alarik_output/")

s3 = boto3.client(
    "s3",
    endpoint_url="http://alarik:8080",
    aws_access_key_id="SUA_ACCESS_KEY",
    aws_secret_access_key="SUA_SECRET_KEY",
)

for root, dirs, files in os.walk("/tmp/alarik_output"):
    for f in files:
        local = os.path.join(root, f)
        key = "destino/" + os.path.relpath(local, "/tmp/alarik_output")
        s3.upload_file(local, "bronze", key)
        print(f"Uploaded: {key}")

print("Sucesso!")
Helper reutilizavel:
python
import boto3
import os
import shutil

def spark_write_to_alarik(df, bucket, prefix, mode="overwrite",
                          fmt="parquet", endpoint="http://alarik:8080",
                          access_key="SUA_ACCESS_KEY",
                          secret_key="SUA_SECRET_KEY"):
    tmp = "/tmp/spark_alarik_staging"
    if os.path.exists(tmp):
        shutil.rmtree(tmp)

    writer = df.write.mode(mode)
    getattr(writer, fmt)(tmp)

    s3 = boto3.client("s3", endpoint_url=endpoint,
                      aws_access_key_id=access_key,
                      aws_secret_access_key=secret_key)

    prefix = prefix.strip("/")
    uploaded = 0
    for root, dirs, files in os.walk(tmp):
        for f in files:
            local = os.path.join(root, f)
            key = f"{prefix}/{os.path.relpath(local, tmp)}"
            s3.upload_file(local, bucket, key)
            uploaded += 1

    shutil.rmtree(tmp)
    print(f"Uploaded {uploaded} files to s3://{bucket}/{prefix}/")

spark_write_to_alarik(df, "bronze", "meu_dataset/")
Resumo: APIs S3 que o Alarik NAO suporta corretamente
API S3	Status no Alarik	Impacto
PutObject	OK	Escrita simples funciona
GetObject	OK	Leitura funciona
HeadObject	BUGADO - retorna 200 para paths inexistentes	Quebra mkdirs, exists(), overwrite
CopyObject	Nao funciona	Quebra rename, algorithm v2
DeleteObjects (bulk)	Retorna 404	Quebra cleanup
CompleteMultipartUpload	Trava/timeout	Quebra directory committer
ListObjectsV2	OK	Listagem funciona
Resumo: Committers testados
Committer	Resultado	Motivo da falha
FileOutputCommitter v1	FALHA	Rename nao suportado
FileOutputCommitter v2	FALHA	CopyObject nao suportado
S3A Magic Committer	FALHA	HeadObject bugado -> mkdirs falha
S3A Directory Committer	TRAVA	CompleteMultipartUpload nao completa
Local + boto3 upload	FUNCIONA	Usa apenas PutObject
Configuracao para Leitura (funciona)
python
spark = SparkSession.builder \
    .config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.access.key", "SUA_ACCESS_KEY") \
    .config("spark.hadoop.fs.s3a.secret.key", "SUA_SECRET_KEY") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.bucket.probe", "0") \
    .getOrCreate()

df = spark.read.parquet("s3a://bronze/meu_dataset/")












# DOCKER COMPOSE YML 



# ══════════════════════════════════════════════════════════════════════
# DOCKER COMPOSE — CLUSTER SPARK + HDFS
# ══════════════════════════════════════════════════════════════════════
#
# Docker Compose é uma ferramenta que define e gerencia
# MÚLTIPLOS containers como uma unidade (um "stack").
#
# Sem Compose: você rodaria 6 comandos "docker run" separados,
# cada um com ~10 flags. Compose centraliza tudo em 1 arquivo.
#
# Arquitetura do cluster:
#
#   ┌─────────────┐     ┌──────────────┐     ┌──────────────┐
#   │   Jupyter    │────▶│ Spark Master │────▶│  Worker 1    │
#   │  (Driver)    │     │  (Scheduler) │────▶│  Worker 2    │
#   └─────────────┘     └──────────────┘     └──────────────┘
#                              │
#   ┌──────────────┐     ┌──────────────┐
#   │ HDFS DataNode│◀───▶│HDFS NameNode │
#   │  (Blocos)    │     │  (Índice)    │
#   └──────────────┘     └──────────────┘
#
# Comandos:
#   docker compose up -d --build   → builda imagens e sobe tudo
#   docker compose down            → para e remove containers
#   docker compose down -v         → idem + apaga volumes (HDFS!)
#   docker compose logs -f         → mostra logs em tempo real
#   docker compose ps              → lista containers e status
# ══════════════════════════════════════════════════════════════════════

# services: → lista de containers que compõem o stack.
# Cada item abaixo vira um container Docker separado.
services:

  # ── SPARK MASTER ────────────────────────────────────────────────────
  #
  # Papel do Master:
  #   - Receber jobs de clientes (Jupyter, spark-submit)
  #   - Dividir cada job em tarefas menores
  #   - Alocar tarefas nos Workers disponíveis
  #   - Monitorar progresso e falhas
  #   - NÃO processa dados (é apenas o coordenador)
  spark-master:

    # build: ./spark → diz ao Compose para CONSTRUIR a imagem
    #   a partir do Dockerfile em ./spark/Dockerfile.
    #
    # Diferente de "image:" que baixa uma imagem pronta do Docker Hub.
    # Com "build:", o Compose roda "docker build ./spark" automaticamente.
    #
    # Se você mudar o Dockerfile, precisa rodar:
    #   docker compose up -d --build
    # para reconstruir a imagem.
    #build: ./spark
    image: spark-custom:latest
    # container_name → nome fixo para o container.
    #   Sem isso, o Compose gera nomes como "cluster-spark-master-1".
    #   Com nome fixo: "docker logs spark-master" funciona direto.
    #   TAMBÉM é o hostname DNS na rede interna (spark-net).
    #   Workers usam "spark-master" para se conectar.
    container_name: spark-master

    # command → substitui o CMD do Dockerfile.
    #   O ENTRYPOINT (tini --) permanece; o command é passado como argumento.
    #   Container executa: tini -- spark-class org.apache.spark.deploy.master.Master
    #
    # spark-class → script launcher do Spark.
    #   Configura classpath, JVM options, e executa a classe Java especificada.
    #
    # org.apache.spark.deploy.master.Master → classe Java do Spark Master.
    #   Inicia o processo que escuta na porta 7077 (RPC) e 8080 (UI).
    command: ["spark-class", "org.apache.spark.deploy.master.Master"]

    # environment → variáveis de ambiente injetadas no container.
    #   Equivalente a "docker run -e SPARK_LOG_LEVEL=WARN".
    #
    # SPARK_LOG_LEVEL=WARN
    #   Controla a verbosidade dos logs do Spark.
    #   Níveis (do mais ao menos verboso):
    #     TRACE → DEBUG → INFO → WARN → ERROR → FATAL
    #   INFO (padrão) mostra TUDO: cada tarefa, cada byte lido, cada shuffle.
    #   WARN mostra apenas avisos e erros → logs limpos para desenvolvimento.
    environment:
      - SPARK_LOG_LEVEL=WARN

    # ports → mapeia portas do container para o host.
    #   Formato: "HOST:CONTAINER"
    #
    # "8080:8080"
    #   O Spark Master escuta na porta 8080 DENTRO do container.
    #   Mapeia para 8080 no host → acessível via http://localhost:8080
    #   Mostra: Workers registrados, jobs em execução, métricas.
    #
    # "7077:7077"
    #   Porta RPC (Remote Procedure Call) do Spark.
    #   Workers se registram aqui: spark://spark-master:7077
    #   Clientes enviam jobs aqui.
    #   Protocolo binário proprietário do Spark (não HTTP).
    #   Exposta no host para permitir spark-submit externo (opcional).
    ports:
      - "8080:8080"
      - "7077:7077"

    # volumes → monta diretórios do host dentro do container.
    #   Formato: "CAMINHO_HOST:CAMINHO_CONTAINER"
    #   Isso é um "bind mount" — mapeamento direto de diretório.
    #
    # ./data:/opt/spark/data
    #   Qualquer arquivo em ./data no seu computador aparece
    #   em /opt/spark/data dentro do container (e vice-versa).
    #   Mudanças são refletidas em tempo real nos dois lados.
    #   Usado para: datasets de entrada, arquivos Parquet, CSVs.
    #
    # ./delta-lake:/opt/spark/delta-lake
    #   Pasta dedicada para tabelas Delta Lake.
    #   Delta Lake salva dados como arquivos Parquet + logs de transação.
    #   Separar de ./data mantém a organização.
    volumes:
      - ./data:/opt/spark/data
      - ./delta-lake:/opt/spark/delta-lake

    # networks → redes virtuais que este container participa.
    #   Todos os containers do cluster devem estar na mesma rede.
    #   Sem rede compartilhada, containers não se enxergam.
    networks:
      - spark-net

  # ── SPARK WORKER 1 ──────────────────────────────────────────────────
  #
  # Papel do Worker:
  #   - EXECUTAR as tarefas que o Master distribui
  #   - Processar dados em paralelo (transformações, agregações)
  #   - Armazenar resultados intermediários (shuffle data)
  #   - Reportar status ao Master via heartbeat
  #
  # Analogia:
  #   Master = gerente de obra (distribui tarefas)
  #   Worker = pedreiro (faz o serviço)
  spark-worker-1:
    #build: ./spark
    image: spark-custom:latest
    container_name: spark-worker-1

    # O último argumento (spark://spark-master:7077) é o endereço do Master.
    #
    # Quando o Worker inicia:
    #   1. Resolve "spark-master" via DNS do Docker → IP interno
    #   2. Conecta na porta 7077 (RPC)
    #   3. Envia mensagem de registro: "sou Worker, tenho 2 cores e 3GB"
    #   4. Master adiciona Worker à lista de recursos disponíveis
    #   5. Worker fica aguardando tarefas
    command: ["spark-class", "org.apache.spark.deploy.worker.Worker", "spark://spark-master:7077"]

    environment:
      # SPARK_WORKER_MEMORY=3g
      #   RAM máxima que este Worker OFERECE para jobs.
      #   Não é RAM reservada — é o limite que o Worker reporta ao Master.
      #   O Master não vai alocar mais que 3GB de tarefas neste Worker.
      #   Se um job pedir 5GB, o Master usa 2 Workers.
      #   "g" = gigabytes. Aceita também "m" (megabytes).
      - SPARK_WORKER_MEMORY=3g

      # SPARK_WORKER_CORES=2
      #   Número de cores de CPU que este Worker disponibiliza.
      #   Cada task do Spark usa 1 core por padrão.
      #   2 cores = este Worker executa até 2 tasks simultaneamente.
      #   Mais tasks por Worker = mais paralelismo, mas cada task tem menos CPU.
      - SPARK_WORKER_CORES=2
      - SPARK_LOG_LEVEL=WARN

    # "8081:8081" → UI individual deste Worker.
    #   Mostra: tasks em execução, memória usada, logs de executors.
    #   Útil para debugar problemas de performance em um Worker específico.
    ports:
      - "8081:8081"

    volumes:
      - ./data:/opt/spark/data
      - ./delta-lake:/opt/spark/delta-lake

    # depends_on → define ordem de inicialização.
    #   O Worker SÓ inicia DEPOIS que o Master estiver rodando.
    #
    #   ⚠️ depends_on verifica apenas se o container INICIOU,
    #   não se o processo dentro dele está PRONTO.
    #   O Worker pode iniciar antes do Master estar escutando na 7077.
    #   Mas o Worker faz retry automático, então funciona.
    #
    #   Para garantia total: use healthcheck + condition: service_healthy.
    depends_on:
      - spark-master

    networks:
      - spark-net

  # ── SPARK WORKER 2 ──────────────────────────────────────────────────
  #
  # Cópia exata do Worker 1, mas em container separado.
  #
  # Por que 2 Workers?
  #   - Simula um cluster real (produção tem dezenas/centenas)
  #   - Permite paralelismo real: Worker 1 e Worker 2 processam
  #     partições diferentes dos dados ao mesmo tempo
  #   - Total: 4 cores + 6GB disponíveis para jobs
  spark-worker-2:
    #build: ./spark
    image: spark-custom:latest
    container_name: spark-worker-2
    command: ["spark-class", "org.apache.spark.deploy.worker.Worker", "spark://spark-master:7077"]
    environment:
      - SPARK_WORKER_MEMORY=3g
      - SPARK_WORKER_CORES=2
      - SPARK_LOG_LEVEL=WARN

    # "8082:8081" → mapeamento com porta diferente no host.
    #
    #   CONTAINER: escuta em 8081 (padrão do Worker, não muda)
    #   HOST: mapeia para 8082 (porque 8081 já é do Worker 1)
    #
    #   Dentro da rede Docker: spark-worker-2:8081 funciona normalmente.
    #   No seu browser: http://localhost:8082
    #
    #   Se usasse "8081:8081", Docker daria erro:
    #     "Bind for 0.0.0.0:8081 failed: port is already allocated"
    ports:
      - "8082:8081"

    volumes:
      - ./data:/opt/spark/data
      - ./delta-lake:/opt/spark/delta-lake
    depends_on:
      - spark-master
    networks:
      - spark-net

  # ── JUPYTER + PYSPARK ───────────────────────────────────────────────
  #
  # Interface interativa onde você escreve código PySpark.
  #
  # O Jupyter é o DRIVER do Spark:
  #   - Cria o SparkSession (conexão com o cluster)
  #   - Serializa suas funções Python
  #   - Envia para o Master, que distribui para Workers
  #   - Recebe resultados e mostra no notebook
  #
  # Fluxo:
  #   Você (browser) → Jupyter (container) → Spark Master → Workers
  #                                                         ↓
  #   Resultado no notebook ← Jupyter ← Spark Master ← Workers
  jupyter:
    #build: ./jupyter
    image: jupyter:latest 
    container_name: jupyter

    environment:
      # PYSPARK_SUBMIT_ARGS → argumentos passados automaticamente
      #   quando PySpark cria um SparkSession.
      #
      # É equivalente a rodar:
      #   spark-submit --master spark://spark-master:7077 \
      #                --packages io.delta:delta-spark_2.12:3.1.0 \
      #                pyspark-shell
      #
      # Detalhamento:
      #
      # --master spark://spark-master:7077
      #   Diz ao PySpark para se conectar ao cluster remoto.
      #   Sem isso, PySpark roda em "local mode" (usa apenas o container Jupyter).
      #   Com isso, as tarefas são executadas nos Workers do cluster.
      #
      # --packages io.delta:delta-spark_2.12:3.1.0
      #   Baixa automaticamente o JAR do Delta Lake do Maven Central.
      #   Formato: groupId:artifactId:version
      #     io.delta       → organização/empresa (Delta Lake project)
      #     delta-spark    → nome do artefato
      #     _2.12          → compilado para Scala 2.12 (Spark 3.5 usa Scala 2.12)
      #     3.1.0          → versão do Delta Lake
      #   Na primeira execução, baixa ~10MB de JARs para ~/.ivy2/
      #   Nas execuções seguintes, usa cache.
      #
      # pyspark-shell
      #   Modo de execução: shell interativo (REPL).
      #   Necessário para funcionar com Jupyter.
      #   Alternativa: "pyspark" (modo script, não interativo).
      - PYSPARK_SUBMIT_ARGS=--master spark://spark-master:7077 --packages io.delta:delta-spark_2.12:3.1.0 pyspark-shell

    ports:
      # http://localhost:8888?token=spark123
      - "8888:8888"

    volumes:
      # ./notebooks:/home/jovyan/work
      #   Seus notebooks .ipynb ficam em ./notebooks no host.
      #   O Jupyter mostra /home/jovyan/work como diretório raiz.
      #   Se você destruir o container, os notebooks estão salvos.
      - ./notebooks:/home/jovyan/work

      # ./data e ./delta-lake → mesmos dados que Spark e HDFS acessam.
      #   Permite ler/escrever arquivos locais diretamente do notebook.
      - ./data:/home/jovyan/data
      - ./delta-lake:/home/jovyan/delta-lake

    depends_on:
      - spark-master
    networks:
      - spark-net

  # ── HDFS NAMENODE ───────────────────────────────────────────────────
  #
  # Papel do NameNode:
  #   - Manter o NAMESPACE (índice) de todos os arquivos do HDFS
  #   - Saber qual bloco de cada arquivo está em qual DataNode
  #   - Gerenciar permissões, criação/exclusão de arquivos
  #   - Coordenar replicação de blocos
  #
  # O que NÃO faz:
  #   - NÃO armazena dados reais (apenas metadados)
  #   - NÃO transfere dados entre clientes e DataNodes
  #
  # Se o NameNode perder seus dados → TODO o HDFS é perdido.
  # (DataNodes têm os blocos, mas sem o índice não sabem o que é o quê)
  hdfs-namenode:
    #build: ./hadoop
    image: hadoop:latest
    container_name: hdfs-namenode

    # entrypoint → substitui o ENTRYPOINT do Dockerfile.
    #
    # > (yaml folded scalar) → texto multi-linha colapsado em uma string.
    #
    # tini -- bash -c "..."
    #   tini como PID 1 (mesmo padrão dos outros containers).
    #   bash -c "..." executa o script inline.
    #
    # Lógica do script:
    #
    #   if [ ! -d /tmp/hadoop-root/dfs/name/current ]; then
    #     → Verifica se o diretório "current" NÃO existe.
    #     → "current" é criado pelo "hdfs namenode -format".
    #     → Se NÃO existe = primeira execução = precisa formatar.
    #
    #   hdfs namenode -format -force
    #     → "Formata" o namespace do HDFS (como formatar um HD).
    #     → Cria a estrutura inicial de metadados (fsimage, edits).
    #     → -force → não pede confirmação (Y/N) interativa.
    #     → Deve rodar APENAS uma vez (na primeira execução).
    #
    #   fi; hdfs namenode
    #     → Inicia o processo do NameNode.
    #     → Fica escutando na porta 8020 (RPC) e 9870 (UI).
    #     → Processo foreground (não retorna enquanto estiver rodando).
    #
    # Por que essa lógica condicional?
    #   Sem ela:
    #     1ª execução: formata + inicia → funciona ✓
    #     2ª execução: tenta formatar de novo → SOBRESCREVE metadados ✗
    #   Com ela:
    #     1ª execução: current não existe → formata → inicia ✓
    #     2ª execução: current existe → pula formato → inicia ✓
    entrypoint: >
      tini -- bash -c "
        if [ ! -d /tmp/hadoop-root/dfs/name/current ]; then
          hdfs namenode -format -force;
        fi;
        hdfs namenode
      "

    ports:
      # 9870 → UI web do HDFS.
      #   http://localhost:9870
      #   Mostra: capacidade total, blocos, DataNodes ativos,
      #   permite navegar pelos diretórios do HDFS.
      - "9870:9870"

      # 8020 → porta RPC (Inter-Process Communication).
      #   DataNodes se registram aqui.
      #   Clientes (Spark, hdfs dfs) se conectam aqui para operações de arquivo.
      #   Protocolo: Hadoop RPC (binário, não HTTP).
      - "8020:8020"

    volumes:
      # Volume NOMEADO (diferente de bind mount).
      #
      # Bind mount (./data:/opt/...):
      #   → Pasta no SEU computador
      #   → Você vê e edita os arquivos direto
      #
      # Volume nomeado (hdfs-namenode-data):
      #   → Docker gerencia internamente
      #   → Armazenado em /var/lib/docker/volumes/ (Linux)
      #   → Você NÃO acessa direto pelo file explorer
      #   → Melhor performance (especialmente Docker Desktop Mac/Windows)
      #   → Ideal para dados internos de sistemas
      #
      # /tmp/hadoop-root/dfs/name → onde o NameNode salva:
      #   - fsimage: snapshot do namespace (árvore de diretórios + metadados)
      #   - edits: log de transações desde o último snapshot
      #   - Juntos, permitem reconstruir o estado completo do HDFS
      - hdfs-namenode-data:/tmp/hadoop-root/dfs/name

    networks:
      - spark-net

  # ── HDFS DATANODE ───────────────────────────────────────────────────
  #
  # Papel do DataNode:
  #   - Armazenar BLOCOS de dados fisicamente em disco
  #   - Responder a leituras e escritas de clientes
  #   - Enviar heartbeat ao NameNode a cada 3 segundos
  #     ("estou vivo e tenho estes blocos: [lista]")
  #   - Verificar integridade dos dados (checksums CRC32)
  #   - Replicar blocos quando o NameNode pede
  #
  # Como os dados são armazenados:
  #   Arquivo de 350MB → dividido em 3 blocos:
  #     Bloco 1: 128MB → DataNode salva como arquivo no disco
  #     Bloco 2: 128MB → idem
  #     Bloco 3:  94MB → idem (último bloco pode ser menor)
  #
  #   Em produção (3 DataNodes, replicação 3):
  #     Cada bloco existe em 3 DataNodes diferentes.
  #     Se um DataNode morrer, os dados ainda existem em outros 2.
  #
  #   Aqui (1 DataNode, replicação 1):
  #     Se o DataNode morrer, os dados se perdem.
  #     OK para desenvolvimento; NUNCA faça isso em produção.
  hdfs-datanode:
    #build: ./hadoop
    image: hadoop:latest
    container_name: hdfs-datanode
    restart: always
    # Simples: apenas inicia o processo do DataNode.
    # Não precisa de lógica condicional como o NameNode
    # (DataNode não tem "format").
    command: ["hdfs", "datanode"]
    environment:
      # CORE_CONF_fs_defaultFS → mecanismo do Docker Hadoop
      #   para gerar configuração XML automaticamente.
      #
      # O Hadoop lê suas configs de arquivos XML:
      #   core-site.xml, hdfs-site.xml, yarn-site.xml, etc.
      #
      # A imagem converte variáveis de ambiente em XML:
      #   CORE_CONF_fs_defaultFS=hdfs://hdfs-namenode:8020
      #   se transforma em (dentro de core-site.xml):
      #     <configuration>
      #       <property>
      #         <name>fs.defaultFS</name>
      #         <value>hdfs://hdfs-namenode:8020</value>
      #       </property>
      #     </configuration>
      #
      # Regra de conversão:
      #   CORE_CONF_ → escreve em core-site.xml
      #   HDFS_CONF_ → escreve em hdfs-site.xml
      #   fs_defaultFS → substitui _ por . → fs.defaultFS
      #
      # fs.defaultFS = filesystem padrão do Hadoop.
      #   hdfs:// → usa protocolo HDFS
      #   hdfs-namenode → hostname do NameNode (resolvido via DNS Docker)
      #   8020 → porta RPC do NameNode
      #
      # Sem essa configuração, o DataNode não sabe onde está o NameNode
      # e não consegue se registrar.
      - CORE_CONF_fs_defaultFS=hdfs://hdfs-namenode:8020

    ports:
      # 9864 → UI web do DataNode.
      #   http://localhost:9864
      #   Mostra: blocos armazenados, espaço em disco usado/disponível,
      #   status da conexão com NameNode.
      - "9864:9864"
      - "9866:9866"




    volumes:
      # Persiste os blocos de dados entre restarts do container.
      # /tmp/hadoop-root/dfs/data → diretório onde o DataNode salva blocos.
      # Cada bloco é um arquivo binário no disco.
      - hdfs-datanode-data:/tmp/hadoop-root/dfs/data

    depends_on:
      # DataNode precisa do NameNode para se registrar.
      # Ao iniciar, DataNode envia bloco report:
      #   "NameNode, sou DataNode X e tenho estes blocos: [lista]"
      - hdfs-namenode

    networks:
      - spark-net

# ══════════════════════════════════════════════════════════════════════
# REDE VIRTUAL
# ══════════════════════════════════════════════════════════════════════
#
# Docker cria uma rede virtual isolada chamada "spark-net".
#
# O que a rede faz:
#   1. DNS interno: cada container é resolvido pelo nome.
#      spark-worker-1 pode pingar "spark-master" pelo nome.
#      Docker resolve para o IP interno (ex: 172.18.0.2).
#
#   2. Isolamento: containers fora dessa rede NÃO conseguem
#      se comunicar com os de dentro.
#
#   3. Sem NAT interno: containers se comunicam diretamente,
#      sem overhead de tradução de endereços.
#
# driver: bridge → tipo de rede mais comum.
#   "bridge" cria uma rede virtual no host com interface própria.
#   Containers ganham IPs privados (172.x.x.x).
#   O host consegue acessar containers pelas portas publicadas.
#   Outros computadores na rede NÃO conseguem (a menos que
#   você configure o firewall do host).
#
# Alternativas:
#   host    → container usa a rede do host diretamente (sem isolamento)
#   overlay → rede entre múltiplos hosts Docker (Docker Swarm)
#   none    → sem rede (container isolado)
# ══════════════════════════════════════════════════════════════════════
networks:
  spark-net:
    driver: bridge

# ══════════════════════════════════════════════════════════════════════
# VOLUMES NOMEADOS
# ══════════════════════════════════════════════════════════════════════
#
# Volumes nomeados são gerenciados pelo Docker Engine.
# Ficam armazenados em /var/lib/docker/volumes/<nome>/_data/
#
# Ciclo de vida:
#   docker compose up    → cria volumes (se não existem)
#   docker compose down  → containers removidos, volumes PRESERVADOS
#   docker compose up    → reutiliza volumes existentes (dados intactos)
#   docker compose down -v → remove containers E volumes (dados PERDIDOS)
#
# Para inspecionar:
#   docker volume ls                    → lista todos os volumes
#   docker volume inspect <nome>        → mostra metadados e caminho
#
# Para limpar volumes orfãos:
#   docker volume prune                 → remove volumes não utilizados
#
# Comparação bind mount vs volume nomeado:
#
#   Bind mount (./data:/opt/spark/data):
#     ✓ Você controla a pasta
#     ✓ Editável no editor/IDE
#     ✓ Visível no file explorer
#     ✗ Performance pode ser ruim no Docker Desktop (Mac/Windows)
#     → Bom para: dados de trabalho, código, notebooks
#
#   Volume nomeado (hdfs-namenode-data):
#     ✓ Melhor performance (bypass do filesystem do host no Mac/Win)
#     ✓ Docker gerencia backup e lifecycle
#     ✗ Não acessível direto pelo explorer
#     ✗ Precisa de "docker cp" para extrair dados
#     → Bom para: dados internos de sistemas (DBs, caches, metadados)
# ══════════════════════════════════════════════════════════════════════
volumes:
  # Metadados do HDFS: namespace completo, edit logs, fsimage.
  # Se perder este volume, perde o índice de TODOS os arquivos do HDFS.
  hdfs-namenode-data:

  # Blocos de dados reais (arquivos divididos em chunks de 128MB).
  # Se perder este volume, perde os dados armazenados no HDFS.
  hdfs-datanode-data:

  # Dados persistentes do Alarik (uploads, banco, configurações).
  # Sobrevive a "docker compose down"; perdido com "docker compose down -v".
  alarik-storage:










  O spark-shared e um volume Docker compartilhado — uma "pasta virtual" que existe dentro do Docker e e montada no mesmo caminho (/tmp/spark-shared) em todos os containers simultaneamente.

O que muda na pratica:

text
Antes (sem volume compartilhado):
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Worker 1   │  │  Worker 2   │  │   Jupyter   │
│ /tmp/foo/   │  │ /tmp/foo/   │  │ /tmp/foo/   │
│ (disco A)   │  │ (disco B)   │  │ (disco C)   │
└─────────────┘  └─────────────┘  └─────────────┘
Cada container tem seu proprio /tmp isolado.
Worker 1 escreve arquivo X → Jupyter NAO ve arquivo X.

Depois (com volume compartilhado):
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Worker 1   │  │  Worker 2   │  │   Jupyter   │
│  /tmp/      │  │  /tmp/      │  │  /tmp/      │
│  spark-     │  │  spark-     │  │  spark-     │
│  shared/ ───┼──┼─ shared/ ───┼──┼─ shared/    │
└─────────────┘  └─────────────┘  └─────────────┘
              ↓        ↓        ↓
         ┌──────────────────────────┐
         │   MESMO DISCO (volume)   │
         │   spark-shared           │
         └──────────────────────────┘
Worker 1 escreve arquivo X → Jupyter VE arquivo X.
Por que isso resolve o problema:

Spark manda os workers escreverem parquet em file:///tmp/spark-shared/alarik_staging/
Worker 1 cria part-00000.parquet, Worker 2 cria part-00001.parquet
Ambos vao para o mesmo volume fisico
Jupyter le os arquivos do mesmo volume e faz upload via boto3 para o Alarik
Sem isso, os workers escrevem nos seus discos locais isolados, e o Jupyter so ve o _SUCCESS (que e criado pelo driver/Jupyter), nao os parquet files.















Documentacao Completa: Spark + Alarik (S3-compatible)
Ambiente
Spark: 3.5.8 (cluster Docker: spark-master, spark-worker-1, spark-worker-2)
Jupyter: container separado (driver PySpark)
Alarik: object storage S3-compatible (ghcr.io/achtungsoftware/alarik)
Hadoop/HDFS: 3.3.4 (hdfs-namenode, hdfs-datanode)
OS Host: Ubuntu (asus-VivoBook-S14-X430UN)
Problema 1: UnknownHostException - bronze.alarik
Erro: java.net.UnknownHostException: bronze.alarik: Name or service not known

Causa: O AWS SDK usa virtual-hosted-style URLs por padrao, transformando o bucket em subdominio: http://bronze.alarik:8085. Como nao existe DNS para bronze.alarik, falha.

Solucao: Forcar path-style access:

python
.config("spark.hadoop.fs.s3a.path.style.access", "true")
Importante: A config deve estar no builder da SparkSession, nao via spark.conf.set(), pois o S3AFileSystem cacheia na primeira chamada e ignora configs posteriores.

Problema 2: Connection Refused na porta 8085
Erro: Connect to alarik:8085 [alarik/172.18.0.3] failed: Connection refused

Causa: O container Alarik mapeia 8085->8080 (externo->interno). Dentro da rede Docker, containers se comunicam pela porta interna (8080).

Solucao:

python
.config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080")
Problema 3: 403 Forbidden
Erro: AmazonS3Exception: Forbidden (Status Code: 403)

Causa: Credenciais incorretas (placeholder em vez da chave real) ou access key sem permissao no bucket.

Solucao: Usar credenciais corretas geradas no Console do Alarik (http://localhost:3005).

Problema 4: _temporary - Could not rename
Erro: java.io.IOException: Could not rename s3a://bronze/test_debug/_temporary/...

Causa: O FileOutputCommitter padrao do Spark usa rename de diretorios. O Alarik nao suporta rename atomico (diferente do S3/MinIO).

Solucao tentada: Usar S3A committers (magic/directory). Requer JAR spark-hadoop-cloud.

Problema 5: ClassNotFoundException - PathOutputCommitProtocol
Erro: java.lang.ClassNotFoundException: org.apache.spark.internal.io.cloud.PathOutputCommitProtocol

Causa: JAR spark-hadoop-cloud nao instalado.

Solucao: Instalar o JAR em todos os containers (master, workers, jupyter):

bash
wget -O /tmp/spark-hadoop-cloud_2.12-3.5.5.jar \
  https://repo1.maven.org/maven2/org/apache/spark/spark-hadoop-cloud_2.12/3.5.5/spark-hadoop-cloud_2.12-3.5.5.jar

docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-master:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-1:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar spark-worker-2:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar jupyter:/opt/spark/jars/
docker cp /tmp/spark-hadoop-cloud_2.12-3.5.5.jar \
  jupyter:/usr/local/lib/python3.12/site-packages/pyspark/jars/
Nota: spark.jars.packages via .config() nao funciona quando a JVM ja esta rodando. O JAR precisa estar no classpath antes do inicio.

Problema 6: FileAlreadyExistsException (Magic Committer)
Erro: FileAlreadyExistsException: Can't make directory for path 's3a://bronze/...' since it is a file

Causa: O Alarik retorna 200 OK com metadata no HEAD para qualquer path (mesmo inexistente), fazendo o S3AFileSystem pensar que ja existe como arquivo.

Solucao tentada: Directory committer + bucket.probe=0.

Problema 7: algorithm.version=2 falha com CopyObject
Erro: AmazonS3Exception: The specified key does not exist (NoSuchKey) durante copyFile

Causa: algorithm.version=2 ainda usa CopyObject internamente, que o Alarik nao implementa.

Solucao: Nenhum — Alarik nao suporta CopyObject.

Problema 8: Directory Committer trava no Stage 0
Sintoma: Execucao fica parada em [Stage 0:> (0 + 2) / 2] indefinidamente.

Causa: O directory committer depende de CompleteMultipartUpload, que o Alarik nao implementa corretamente.

Problema 9: Escrita local — Workers em containers separados
Erro: _SUCCESS criado mas sem parquet files (apenas 0 bytes)

Causa: Spark distribui a escrita nos workers (containers remotos). O _SUCCESS e criado pelo driver (Jupyter), mas os parquet files ficam no filesystem local de cada worker. O Jupyter nao ve os arquivos.

Solucao tentada 1 — Volume compartilhado Docker: Adicionado spark-shared:/tmp/spark-shared nos volumes de todos os containers.

Problema 10: Container name conflict ao recriar
Erro: Error response from daemon: Conflict. The container name "/console" is already in use

Causa: Containers antigos (de compose anterior) ainda existiam com os mesmos nomes.

Solucao:

bash
docker rm -f alarik console spark-master spark-worker-1 spark-worker-2 jupyter hdfs-namenode hdfs-datanode
docker compose up -d
Problema 11: Alarik login perdido apos recriar container
Causa: O docker rm -f alarik removeu o container. O volume alarik-storage pode ter sido recriado limpo pelo novo compose, ou o compose do Alarik (separado) cria um volume com nome diferente.

Solucao:

bash
cd ~/Desktop/spark-docker/alarik
docker compose down -v
docker compose up -d
Depois login com alarik/alarik e recriar bucket + access keys.

Problema 12: Permission denied no volume compartilhado
Erro: java.io.FileNotFoundException: /tmp/spark-shared/alarik_staging/... (Permission denied)

Causa: Volume Docker criado com permissoes root. Workers rodam com UID diferente.

Solucao:

bash
docker exec --user root spark-master chmod -R 777 /tmp/spark-shared
docker exec --user root spark-worker-1 chmod -R 777 /tmp/spark-shared
docker exec --user root spark-worker-2 chmod -R 777 /tmp/spark-shared
docker exec --user root jupyter chmod -R 777 /tmp/spark-shared
Problema 13: Failed to rename no volume compartilhado (cross-user)
Erro: java.io.IOException: Failed to rename ... to file:/tmp/spark-shared/alarik_staging/part-00000-...

Causa: O FileOutputCommitter no commit final tenta fazer rename de arquivos escritos pelos workers (UID diferente do driver). O volume Docker nao permite cross-user rename.

Solucao: Usar HDFS como staging em vez do volume compartilhado. HDFS suporta rename atomico e nao tem problemas de UID.

Problema 14: hdfs CLI nao encontrado no Jupyter
Erro: FileNotFoundError: [Errno 2] No such file or directory: 'hdfs'

Causa: Container Jupyter nao tem o hdfs CLI instalado.

Solucao: Usar a API Java do Hadoop via PySpark (spark._jvm.org.apache.hadoop.fs.FileSystem) para copiar arquivos do HDFS para local.

Problema 15: Access Denied no upload boto3
Erro: AccessDenied: An error occurred (AccessDenied) when calling the PutObject operation

Causa: Access key do Alarik sem permissao de escrita no bucket, ou credenciais incorretas (placeholder).

Solucao: No Console do Alarik:

Criar bucket bronze
Gerar access key com permissao de escrita
Atualizar credenciais no codigo
Solucao Final Funcional: HDFS Staging + boto3 Upload
python
from pyspark.sql import SparkSession
import boto3
import os
import shutil

ACCESS_KEY = "SUA_ACCESS_KEY_REAL"
SECRET_KEY = "SUA_SECRET_KEY_REAL"

spark = SparkSession.builder \
    .appName("Alarik") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.access.key", ACCESS_KEY) \
    .config("spark.hadoop.fs.s3a.secret.key", SECRET_KEY) \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .getOrCreate()

def spark_write_to_alarik(df, bucket, prefix):
    hdfs_tmp = "hdfs://hdfs-namenode:8020/tmp/alarik_staging"
    local_tmp = "/tmp/alarik_local_staging"

    df.write.mode("overwrite").parquet(hdfs_tmp)

    if os.path.exists(local_tmp):
        shutil.rmtree(local_tmp)
    os.makedirs(local_tmp)

    fs = spark._jvm.org.apache.hadoop.fs.FileSystem.get(
        spark._jvm.java.net.URI("hdfs://hdfs-namenode:8020"),
        spark._jsc.hadoopConfiguration()
    )
    files = fs.listStatus(spark._jvm.org.apache.hadoop.fs.Path(hdfs_tmp))
    for f in files:
        name = f.getPath().getName()
        if name.startswith("_") or name.startswith("."):
            continue
        fs.copyToLocalFile(False, f.getPath(),
                          spark._jvm.org.apache.hadoop.fs.Path(f"file://{local_tmp}/{name}"))

    s3 = boto3.client("s3", endpoint_url="http://alarik:8080",
                      aws_access_key_id=ACCESS_KEY,
                      aws_secret_access_key=SECRET_KEY)
    prefix = prefix.strip("/")
    for f in os.listdir(local_tmp):
        if f.startswith("_") or f.startswith("."):
            continue
        local = os.path.join(local_tmp, f)
        s3.upload_file(local, bucket, f"{prefix}/{f}")
        print(f"Uploaded: {prefix}/{f} ({os.path.getsize(local)} bytes)")

    fs.delete(spark._jvm.org.apache.hadoop.fs.Path(hdfs_tmp), True)
    shutil.rmtree(local_tmp)

data = [("Alice", 30), ("Bob", 25), ("Carol", 35)]
df = spark.createDataFrame(data, ["nome", "idade"])
spark_write_to_alarik(df, "bronze", "pessoas")
Para ler de volta:

python
df = spark.read.parquet("s3a://bronze/pessoas/")
df.show()
Fluxo da Solucao Final
text
1. Spark DataFrame
       ↓ df.write.parquet(hdfs://...)
2. HDFS (staging temporario)
   - Workers escrevem parquet files
   - FileOutputCommitter faz rename (HDFS suporta)
       ↓ fs.copyToLocalFile()
3. Filesystem local do Jupyter (/tmp/)
   - Copia via API Java do Hadoop
       ↓ boto3.upload_file()
4. Alarik (S3-compatible)
   - Upload via PutObject (unica API que funciona)
       ↓ cleanup
5. HDFS staging deletado + /tmp limpo
APIs S3 que o Alarik NAO suporta
API S3	Status	Impacto
PutObject	OK	Escrita simples funciona
GetObject	OK	Leitura funciona
ListObjectsV2	OK	Listagem funciona
HeadObject	BUGADO	Retorna 200 para paths inexistentes
CopyObject	Nao funciona	Quebra rename, algorithm v2
DeleteObjects (bulk)	Retorna 404	Quebra cleanup
CompleteMultipartUpload	Trava/timeout	Quebra directory committer
Committers testados
Committer	Resultado	Motivo
FileOutputCommitter v1	FALHA	Rename nao suportado
FileOutputCommitter v2	FALHA	CopyObject nao suportado
S3A Magic Committer	FALHA	HeadObject bugado
S3A Directory Committer	TRAVA	MultipartUpload nao completa
HDFS staging + boto3	FUNCIONA	Usa apenas PutObject
Configuracao Docker
docker-compose.yml principal (spark-docker/)
Adicionado spark-shared:/tmp/spark-shared em spark-master, spark-worker-1, spark-worker-2, jupyter e declarado volume spark-shared: (necessario para tentativa com volume compartilhado, opcional na solucao final com HDFS).

alarik/docker-compose.yml (separado)
Gerencia Alarik + Console na rede spark-docker_spark-net (externa).

Setup do Alarik:

docker compose up -d no diretorio alarik/
Login http://localhost:3005 com alarik/alarik
Criar bucket bronze
Gerar access key com permissao de escrita
Usar access/secret key no codigo Python
Problemas com Docker (containers orfaos)
Ao mudar entre compose files, containers antigos podem conflitar:

bash
docker rm -f alarik console spark-master spark-worker-1 spark-worker-2 jupyter hdfs-namenode hdfs-datanode
Leitura do Alarik (funciona diretamente)
python
spark = SparkSession.builder \
    .config("spark.hadoop.fs.s3a.endpoint", "http://alarik:8080") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.access.key", "SUA_KEY") \
    .config("spark.hadoop.fs.s3a.secret.key", "SUA_SECRET") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.bucket.probe", "0") \
    .getOrCreate()

df = spark.read.parquet("s3a://bronze/pessoas/")
df.show()






📌 Significados dos termos e bibliotecas

# Variáveis de ambiente do PySpark
- os.environ['PYSPARK_SUBMIT_ARGS'] = (
    '--packages org.apache.hadoop:hadoop-client-api:3.3.4,org.apache.hadoop:hadoop-client-runtime:3.3.4 pyspark-shell'
)
- Diz para o Spark baixar pacotes do Hadoop que permitem usar S3A/RustFS.
- Essencial para ler e escrever em RustFS.


# Configurações do RustFS/S3A
- .config("spark.hadoop.fs.s3a.endpoint", "http://rustfs:9000")
- Diz onde está o RustFS (nome do container + porta).

- .config("spark.hadoop.fs.s3a.access.key", "aVmw0A7JQuK8yMJtuSrQ")
- .config("spark.hadoop.fs.s3a.secret.key", "VkptAAqm25tN1R2henHRWuGmiAgmg21wPtAhCmvZ")
- Chave e segredo para autenticação no RustFS.

- .config("spark.hadoop.fs.s3a.path.style.access", "true")
- Diz para usar o formato http://host:port/bucket/key, necessário para RustFS.

- .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
- Define que o Spark vai usar o driver S3A para acessar RustFS.

-.config("spark.hadoop.fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.
SimpleAWSCredentialsProvider")
- Diz para usar o provedor de credenciais simples, que pega a access.key e secret.key passadas.


# Resumo ainda mais direto
- import os / SparkSession	
- Importa ferramentas necessárias

- PYSPARK_SUBMIT_ARGS	
- Baixa bibliotecas Hadoop para S3/RustFS

- SparkSession.builder	
- Começa a criar Spark

- .appName	
- Nome da aplicação Spark

- fs.s3a.endpoint	
- Onde o RustFS/S3 está (docker container)

- access.key / 
- secret.key	Login no RustFS

- path.style.access	
- Formato de URL que RustFS exige

- fs.s3a.impl	
- Diz para Spark usar driver S3A

- aws.credentials.provider	
- Diz para usar as chaves que você forneceu

- getOrCreate()	
- Cria a sessão Spark

#
```
import os
from pyspark.sql import SparkSession
import os

os.environ['PYSPARK_SUBMIT_ARGS'] = (
    '--packages org.apache.hadoop:hadoop-aws:3.3.4,'
    'com.amazonaws:aws-java-sdk-bundle:1.12.262,'
    'org.apache.hadoop:hadoop-client-api:3.3.4,'
    'org.apache.hadoop:hadoop-client-runtime:3.3.4 '
    'pyspark-shell'
)


os.environ['PYSPARK_SUBMIT_ARGS'] = (
    '--packages '
    'org.apache.hadoop:hadoop-client-api:3.3.4,'
    'org.apache.hadoop:hadoop-client-runtime:3.3.4 '
    'pyspark-shell'
)

spark = SparkSession.builder \
    .appName("RustFS-Spark3.5") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://rustfs:9000" ) \
    .config("spark.hadoop.fs.s3a.access.key", "aVmw0A7JQuK8yMJtuSrQ") \
    .config("spark.hadoop.fs.s3a.secret.key", "VkptAAqm25tN1R2henHRWuGmiAgmg21wPtAhCmvZ") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider") \
    .getOrCreate()

print("Spark 3.5.x configurado com sucesso!")

# Criar um DataFrame de exemplo
data = [("Alice", 1), ("Bob", 2), ("Charlie", 3)]
columns = ["Name", "ID"]

df = spark.createDataFrame(data, columns)

df.write.mode("overwrite").parquet("s3a://yuan/produtos.parquet")

26/03/31 04:36:55 WARN MetricsConfig: Cannot locate configuration: tried hadoop-metrics2-s3a-file-system.properties,hadoop-metrics2.properties
```



# Por que você trocou localhost por rustfs?
localhost dentro de um container é o próprio container
Quando você está no container do Jupyter ou Spark, localhost aponta para ele mesmo, não para outros containers.
Então http://localhost:9000 só tentaria acessar algo no mesmo container, que não existe → erro de conexão.
Containers se comunicam pelo nome do serviço no Docker
No seu docker-compose.yml, o serviço RustFS é chamado rustfs.

Docker cria automaticamente um DNS interno, então de outro container você consegue acessar:

http://rustfs:9000
Isso aponta para o container RustFS, que está escutando na porta 9000.



# Analogia rápida
Você está em uma sala (container Jupyter).
O RustFS está em outra sala (container RustFS).
localhost = olhar para a sua própria sala (não vê RustFS).
rustfs = falar com a outra sala pelo nome (vai encontrar o RustFS).

✅ Por isso, para Spark/Jupyter acessar RustFS dentro do Docker, sempre use o nome do container (rustfs) e não localhost).









# 🚀 Configuração do Spark 3.5 com S3 (RustFS)

Este documento descreve a configuração de uma sessão do **PySpark** integrada com armazenamento compatível com S3 (ex: RustFS), incluindo otimizações de performance, memória e execução.

---

## 🧠 1. Inicialização

```python
SparkSession.builder
.appName("RustFS-Spark3.5")
```

* **SparkSession**: ponto de entrada principal do Spark
* **appName**: nome da aplicação (visível no Spark UI)

---

## ☁️ 2. Configuração S3A (RustFS)

```python
.config("spark.hadoop.fs.s3a.endpoint", "http://rustfs:9000")
```

* Endpoint do serviço S3

```python
.config("spark.hadoop.fs.s3a.access.key", "...")
.config("spark.hadoop.fs.s3a.secret.key", "...")
```

* Credenciais de acesso

```python
.config("spark.hadoop.fs.s3a.path.style.access", "true")
```

* Necessário para compatibilidade com MinIO/RustFS

```python
.config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
```

* Define o conector S3A

```python
.config("spark.hadoop.fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
```

* Usa credenciais definidas manualmente

---

## ⚡ 3. Performance S3

```python
.config("spark.hadoop.fs.s3a.connection.maximum", "100")
```

* Máximo de conexões simultâneas

```python
.config("spark.hadoop.fs.s3a.fast.upload", "true")
```

* Ativa upload multipart

```python
.config("spark.hadoop.fs.s3a.fast.upload.buffer", "disk")
```

* Buffer de upload em disco

```python
.config("spark.hadoop.fs.s3a.multipart.size", "67108864")  # 64MB
```

* Tamanho dos chunks de upload

```python
.config("spark.hadoop.fs.s3a.block.size", "134217728")  # 128MB
```

* Tamanho de leitura de blocos

---

## 🧠 4. Memória

```python
.config("spark.executor.memory", "3g")
```

* Memória por executor

```python
.config("spark.executor.memoryOverhead", "1g")
```

* Memória extra (off-heap)

```python
.config("spark.driver.memory", "2g")
```

* Memória do driver

```python
.config("spark.driver.memoryOverhead", "512m")
```

* Overhead do driver

```python
.config("spark.memory.fraction", "0.8")
```

* Fração para execução + cache

```python
.config("spark.memory.storageFraction", "0.2")
```

* Fração para armazenamento (cache)

---

## 🧮 5. CPU

```python
.config("spark.executor.cores", "2")
```

* Número de núcleos por executor

---

## 🔀 6. Shuffle

```python
.config("spark.sql.shuffle.partitions", "40")
```

* Número de partições para operações de shuffle

```python
.config("spark.shuffle.compress", "true")
.config("spark.shuffle.spill.compress", "true")
```

* Compressão de dados intermediários

```python
.config("spark.io.compression.codec", "lz4")
```

* Codec de compressão (rápido)

---

## ⚡ 7. Serialização

```python
.config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
```

* Serialização mais eficiente

```python
.config("spark.kryoserializer.buffer.max", "256m")
```

* Tamanho máximo do buffer

---

## 🧠 8. Adaptive Query Execution (AQE)

```python
.config("spark.sql.adaptive.enabled", "true")
```

* Otimização automática de queries

```python
.config("spark.sql.adaptive.coalescePartitions.enabled", "true")
```

* Reduz partições pequenas

```python
.config("spark.sql.adaptive.skewJoin.enabled", "true")
```

* Corrige skew em joins

---

## 🚀 Boas práticas

* Usar armazenamento separado para dados (HD/SSD)
* Monitorar via Spark UI (`http://localhost:4040`)
* Ajustar `shuffle.partitions` conforme número de CPUs
* Evitar datasets muito pequenos (causam overhead)

---

## ⚠️ Observações

* Ideal para ambientes self-hosted como CasaOS
* Ajustes podem variar conforme hardware
* Sempre testar performance com dados reais

---

## 📌 Conclusão

Essa configuração fornece:

✅ Boa performance em S3
✅ Uso eficiente de memória
✅ Execução otimizada com AQE
✅ Base sólida para ETL e pipelines de dados

---
