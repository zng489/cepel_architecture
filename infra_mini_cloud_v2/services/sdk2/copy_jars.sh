#!/bin/bash
set -e

JARS_DIR="."

echo "=== Copiando JARs para os containers ==="
for CONTAINER in spark-master spark-worker-1 spark-worker-2 jupyter; do
  echo "→ $CONTAINER"
  docker cp $JARS_DIR/iceberg-spark-runtime-3.5_2.12-1.5.2.jar \
    $CONTAINER:/opt/spark/jars/
  docker cp $JARS_DIR/iceberg-aws-bundle-1.5.2.jar \
    $CONTAINER:/opt/spark/jars/
done

echo "=== Verificando ==="
docker exec spark-master ls /opt/spark/jars/ | grep iceberg

echo "=== Pronto chmod +x copy_jars.sh ./copy_jars.sh 
for CONTAINER in spark-master spark-worker-1 spark-worker-2 jupyter; do
  echo "→ $CONTAINER"
  docker exec $CONTAINER ls /opt/spark/jars/ | grep iceberg
done

chmod +x copy_jars.sh
./copy_jars.sh

==="