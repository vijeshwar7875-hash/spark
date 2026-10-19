#!/bin/bash
set -e
ARCH=$(dpkg --print-architecture)   # amd64 or arm64 (auto)
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-$ARCH
export HADOOP_HOME=/usr/local/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
add_env() { grep -qxF "$1" ~/.bashrc || echo "$1" >> ~/.bashrc; }

echo "=== 1. Install Java, SSH, tools ==="
sudo apt update
sudo apt install -y curl wget git unzip build-essential nano openjdk-11-jdk openssh-server
java -version

echo "=== 2. Passwordless SSH ==="
sudo service ssh start
mkdir -p ~/.ssh && chmod 700 ~/.ssh
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
grep -qF "$(cat ~/.ssh/id_ed25519.pub)" ~/.ssh/authorized_keys 2>/dev/null || cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
ssh -o StrictHostKeyChecking=no localhost exit

echo "=== 3. Environment variables ==="
add_env "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-$ARCH"
add_env 'export HADOOP_HOME=/usr/local/hadoop'
add_env 'export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin'

echo "=== 4. Download and install Hadoop 3.3.6 ==="
if [ ! -d "$HADOOP_HOME" ]; then
  mkdir -p ~/Downloads && cd ~/Downloads
  wget -nc https://archive.apache.org/dist/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
  tar -xzf hadoop-3.3.6.tar.gz
  sudo mv hadoop-3.3.6 "$HADOOP_HOME"
  sudo chown -R "$USER":"$USER" "$HADOOP_HOME"
fi
hadoop version

echo "=== 5. Configure Hadoop ==="
grep -qF "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-$ARCH" $HADOOP_HOME/etc/hadoop/hadoop-env.sh || \
  echo "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-$ARCH" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh

cat > $HADOOP_HOME/etc/hadoop/core-site.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://localhost:9000</value>
  </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/hdfs-site.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>file:/usr/local/hadoop/hadoop_data/hdfs/namenode</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>file:/usr/local/hadoop/hadoop_data/hdfs/datanode</value>
  </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/mapred-site.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
  <property>
    <name>mapreduce.application.classpath</name>
    <value>$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value>
  </property>
  <property>
    <name>yarn.app.mapreduce.am.env</name>
    <value>HADOOP_MAPRED_HOME=/usr/local/hadoop</value>
  </property>
  <property>
    <name>mapreduce.map.env</name>
    <value>HADOOP_MAPRED_HOME=/usr/local/hadoop</value>
  </property>
  <property>
    <name>mapreduce.reduce.env</name>
    <value>HADOOP_MAPRED_HOME=/usr/local/hadoop</value>
  </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/yarn-site.xml <<'EOF'
<?xml version="1.0"?>
<configuration>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
</configuration>
EOF

echo "=== 6. Format (first time only) and start Hadoop ==="
mkdir -p $HADOOP_HOME/hadoop_data/hdfs/namenode $HADOOP_HOME/hadoop_data/hdfs/datanode
[ -d $HADOOP_HOME/hadoop_data/hdfs/namenode/current ] || hdfs namenode -format
jps | grep -q NameNode || start-dfs.sh
jps | grep -q ResourceManager || start-yarn.sh
hdfs dfsadmin -safemode wait
jps
echo "HDFS UI: http://localhost:9870 | YARN UI: http://localhost:8088"

echo "=== 7. Download and install Spark 3.5.3 ==="
export SPARK_HOME=/usr/local/spark
export PATH=$PATH:$SPARK_HOME/bin
if [ ! -d "$SPARK_HOME" ]; then
  mkdir -p ~/Downloads && cd ~/Downloads
  wget -nc https://archive.apache.org/dist/spark/spark-3.5.3/spark-3.5.3-bin-hadoop3.tgz
  tar -xzf spark-3.5.3-bin-hadoop3.tgz
  sudo mv spark-3.5.3-bin-hadoop3 "$SPARK_HOME"
  sudo chown -R "$USER":"$USER" "$SPARK_HOME"
fi
add_env 'export SPARK_HOME=/usr/local/spark'
add_env 'export PATH=$PATH:$SPARK_HOME/bin'
spark-shell --version

echo "=== 8. Input files ==="
mkdir -p ~/sparklab && cd ~/sparklab
printf 'cloud computing cloud lab\nspark processes data\n' > input.txt
hdfs dfs -mkdir -p /input
hdfs dfs -put -f input.txt /input/input.txt

echo "=== 9. Word count: local file ==="
rm -rf ~/sparklab/output
cat > local_wc.scala <<'EOF'
val inputFile = sc.textFile("input.txt")
val counts = inputFile.flatMap(line => line.split("\\s+")).filter(_.nonEmpty).map(word => (word, 1)).reduceByKey(_ + _)
counts.collect().foreach(println)
counts.saveAsTextFile("output")
sys.exit(0)
EOF
spark-shell --master local[2] -i local_wc.scala < /dev/null
echo "----- LOCAL OUTPUT -----"
cat ~/sparklab/output/part-*

echo "=== 10. Word count: HDFS ==="
hdfs dfs -rm -r -f /output/spark-wordcount
cat > hdfs_wc.scala <<'EOF'
val hdfsInput = sc.textFile("hdfs://localhost:9000/input/input.txt")
val hdfsCounts = hdfsInput.flatMap(line => line.split("\\s+")).filter(_.nonEmpty).map(word => (word, 1)).reduceByKey(_ + _)
hdfsCounts.collect().foreach(println)
hdfsCounts.saveAsTextFile("hdfs://localhost:9000/output/spark-wordcount")
sys.exit(0)
EOF
spark-shell --master local[2] -i hdfs_wc.scala < /dev/null
echo "----- HDFS OUTPUT -----"
hdfs dfs -cat /output/spark-wordcount/part-*
echo "DONE. Stop Hadoop with: stop-yarn.sh && stop-dfs.sh"
