#!/bin/bash
set -e

ICEBERG_VERSION="1.5.2"
MAVEN="https://repo1.maven.org/maven2"
JARS_DIR="/tmp/jars_polaris"

mkdir -p $JARS_DIR

echo "=== Baixando JARs Polaris ==="

curl -o $JARS_DIR/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar \
  $MAVEN/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar

curl -o $JARS_DIR/iceberg-aws-bundle-${ICEBERG_VERSION}.jar \
  $MAVEN/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar

echo "=== Removendo JARs conflitantes (SDK v1) ==="

for CONTAINER in spark-master spark-worker-1 spark-worker-2 jupyter; do
  echo "→ $CONTAINER"
  docker exec -u root $CONTAINER rm -f \
    /opt/spark/jars/hadoop-aws-*.jar \
    /opt/spark/jars/aws-java-sdk-bundle-*.jar
  docker cp $JARS_DIR/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar $CONTAINER:/opt/spark/jars/
  docker cp $JARS_DIR/iceberg-aws-bundle-${ICEBERG_VERSION}.jar             $CONTAINER:/opt/spark/jars/
done

echo "=== Polaris pronto chmod +x setup_jars_polaris.sh  ./setup_jars_polaris.sh ==="




