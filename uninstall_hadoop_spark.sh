#!/bin/bash
# Reverts everything done by hadoop_setup.sh / spark_setup.sh
# Run as normal user:  bash uninstall_hadoop_spark.sh

echo "=== 1. Stop Hadoop daemons ==="
stop-yarn.sh 2>/dev/null
stop-dfs.sh 2>/dev/null
pkill -u "$USER" -f 'org.apache.hadoop' 2>/dev/null
sleep 2

echo "=== 2. Delete Hadoop, Spark and lab folders ==="
sudo rm -rf /usr/local/hadoop /usr/local/spark
rm -rf ~/input ~/wordcount ~/sparklab ~/sparkenv
rm -f ~/Downloads/hadoop-3.3.*.tar.gz ~/Downloads/spark-3.5.*-bin-hadoop3.tgz   # any version downloaded
rm -rf /tmp/hadoop-"$USER" /tmp/hsperfdata_"$USER"

echo "=== 3. Remove lines added to ~/.bashrc (backup saved) ==="
cp ~/.bashrc ~/.bashrc.bak_before_uninstall
sed -i '/HADOOP_HOME/d;/SPARK_HOME/d;/JAVA_HOME=\/usr\/lib\/jvm\/java-11-openjdk/d' ~/.bashrc

echo "=== 4. Optional: remove SSH key made for localhost login ==="
read -rp "Delete ~/.ssh/id_ed25519 and its authorized_keys entry? (y/N) " a
if [ "$a" = "y" ]; then
  PUB=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null)
  [ -n "$PUB" ] && grep -vF "$PUB" ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys
  rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
fi

echo "=== 5. Optional: remove Java 11 and SSH server ==="
read -rp "Run apt remove for openjdk-11-jdk and openssh-server? (y/N) " b
if [ "$b" = "y" ]; then
  sudo service ssh stop
  sudo apt remove -y openjdk-11-jdk openssh-server
  sudo apt autoremove -y
fi

echo "DONE. Open a NEW terminal (or run: exec bash) so old variables are cleared."
