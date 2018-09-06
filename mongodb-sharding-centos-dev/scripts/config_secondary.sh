#!/bin/bash
mongoAdminUser=$1
mongoAdminPasswd=$2
mongoKeyFile='E6JhxBwAXSwhNaz2'

install_mongo3() {
    #install mongo3
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2930ADAE8CAF5059EE73BB4B58712A2291FA4AD5
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.6 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.6.list

    apt update
    sudo apt install -y mongodb-org

    sudo systemctl stop mongod.service


# --------- CONFIG SERVER CONFIG + SERVICE [START] -------------

cat <<EOT > /etc/mongod_configsvr.conf
# mongod.conf

# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# Where and how to store data.
storage:
  dbPath: /var/lib/mongodb/configsvr
  journal:
    enabled: true
#  engine:
#  mmapv1:
#  wiredTiger:

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod_configsvr.log

# network interfaces
net:
  port: 27019
  bindIp: 0.0.0.0

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

replication:
   replSetName: confReplica

sharding:
   clusterRole: configsvr

security:
  keyFile: /etc/mongokeyfile
EOT

cat <<EOT > /lib/systemd/system/mongod.confsvr.service
[Unit]
Description=High-performance, schema-free document-oriented database
After=network.target
Documentation=https://docs.mongodb.org/manual

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod_configsvr.conf
PIDFile=/var/run/mongodb/mongod.confsvr.pid
# file size
LimitFSIZE=infinity
# cpu time
LimitCPU=infinity
# virtual memory size
LimitAS=infinity
# open files
LimitNOFILE=64000
# processes/threads
LimitNPROC=64000
# locked memory
LimitMEMLOCK=infinity
# total threads (user+kernel)
TasksMax=infinity
TasksAccounting=false

# Recommended limits for for mongod as specified in
# http://docs.mongodb.org/manual/reference/ulimit/#recommended-settings

[Install]
WantedBy=multi-user.target
EOT

# --------- CONFIG SERVER CONFIG + SERVICE [END] -------------

# --------- SHARD SERVER CONFIG + SERVICE [START] -------------

cat <<EOT > /etc/mongod_shardsvr.conf
# mongod.conf

# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# Where and how to store data.
storage:
  dbPath: /var/lib/mongodb/shardsvr
  journal:
    enabled: true
#  engine:
#  mmapv1:
#  wiredTiger:

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod_shardsvr.log

# network interfaces
net:
  port: 27018
  bindIp: 0.0.0.0

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

sharding:
   clusterRole: shardsvr

security:
  keyFile: /etc/mongokeyfile
EOT

cat <<EOT > /lib/systemd/system/mongod.shardsvr.service
[Unit]
Description=High-performance, schema-free document-oriented database
After=network.target
Documentation=https://docs.mongodb.org/manual

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod_shardsvr.conf
PIDFile=/var/run/mongodb/mongod.shardsvr.pid
# file size
LimitFSIZE=infinity
# cpu time
LimitCPU=infinity
# virtual memory size
LimitAS=infinity
# open files
LimitNOFILE=64000
# processes/threads
LimitNPROC=64000
# locked memory
LimitMEMLOCK=infinity
# total threads (user+kernel)
TasksMax=infinity
TasksAccounting=false

# Recommended limits for for mongod as specified in
# http://docs.mongodb.org/manual/reference/ulimit/#recommended-settings

[Install]
WantedBy=multi-user.target
EOT

# --------- SHARD SERVER CONFIG + SERVICE [END] -------------

    chmod 644 /lib/systemd/system/mongod.confsvr.service
    chmod 644 /lib/systemd/system/mongod.shardsvr.service

    #create dirs
    mkdir /var/lib/mongodb/configsvr
    chown mongodb:mongodb /var/lib/mongodb/configsvr/
    chmod 755 /var/lib/mongodb/configsvr/
    
    mkdir /var/lib/mongodb/shardsvr
    chown mongodb:mongodb /var/lib/mongodb/shardsvr/
    chmod 755 /var/lib/mongodb/shardsvr/

    #remove default mongo service
    rm /lib/systemd/system/mongod.service

    #enable autostart
    systemctl enable mongod.confsvr.service
    systemctl enable mongod.shardsvr.service
#------------------------------------------------------

	#kernel settings
	if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]];then
		echo never > /sys/kernel/mm/transparent_hugepage/enabled
	fi
	if [[ -f /sys/kernel/mm/transparent_hugepage/defrag ]];then
		echo never > /sys/kernel/mm/transparent_hugepage/defrag
	fi

	#set keyfile
	echo $mongoKeyFile > /etc/mongokeyfile
	chown mongodb:mongodb /etc/mongokeyfile
	chmod 600 /etc/mongokeyfile
}

install_mongo3

    #start config replica set
    systemctl start mongod.confsvr.service
    #start shard as standalone server
    systemctl start mongod.shardsvr.service


    #check if mongod started or not
    sleep 15
    n=`ps -ef |grep "/usr/bin/mongod --config /etc/mongod_configsvr.conf" |grep -v grep |wc -l`
    if [[ $n -eq 1 ]];then
        echo "mongod config replica set started successfully"
    else
        echo "mongod config replica set started failed!"
    fi

    n=`ps -ef |grep "/usr/bin/mongod --config /etc/mongod_shardsvr.conf" |grep -v grep |wc -l`
    if [[ $n -eq 1 ]];then
        echo "mongod config replica set started successfully"
    else
        echo "mongod config replica set started failed!"
    fi

#create mongo shardsvr user
mongo --port 27018 <<EOF
use admin
db.createUser({user:"$mongoAdminUser",pwd:"$mongoAdminPasswd",roles:[{role: "userAdminAnyDatabase", db: "admin" },{role: "readWriteAnyDatabase", db: "admin" },{role: "root", db: "admin" }]})
exit
EOF

#mongo configsvr user is created in primary node (configsvr is a replicaset so no need to set it up on each node)


