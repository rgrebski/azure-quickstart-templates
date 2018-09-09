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


cat <<EOT > /lib/systemd/system/mongod.router.service
[Unit]
Description=High-performance, schema-free document-oriented database
After=network.target
Documentation=https://docs.mongodb.org/manual

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongos --configdb confReplica/10.0.0.240:27019,10.0.0.241:27019,10.0.0.242:27019 --port 27017 --logpath /var/log/mongodb/mongos.log --keyFile /etc/mongokeyfile
PIDFile=/var/run/mongodb/mongod.router.pid
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

    chmod 644 /lib/systemd/system/mongod.router.service

    #remove default mongo service
    rm /lib/systemd/system/mongod.service

    #enable autostart
    systemctl enable mongod.router.service
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
    systemctl start mongod.router.service


    #check if mongod started or not
    sleep 15
    n=`ps -ef |grep "/usr/bin/mongos --configdb confReplica" |grep -v grep |wc -l`
    if [[ $n -eq 1 ]];then
        echo "mongod config replica set started successfully"
    else
        echo "mongod config replica set started failed!"
    fi

mongo --port 27017 <<EOF
use admin
db.createUser({user:"$mongoAdminUser",pwd:"$mongoAdminPasswd",roles:[{role: "userAdminAnyDatabase", db: "admin" },{role: "readWriteAnyDatabase", db: "admin" },{role: "root", db: "admin" }]})
exit
EOF

#add shard
mongo --port 27017 <<EOF
use admin
db.auth("$mongoAdminUser","$mongoAdminPasswd")
sh.addShard("10.0.0.240:27018")
sh.addShard("10.0.0.241:27018")
sh.addShard("10.0.0.242:27018")
sh.addShard("10.0.0.243:27018")
sh.addShard("10.0.0.244:27018")
sh.addShard("10.0.0.245:27018")
sh.addShard("10.0.0.246:27018")
sh.addShard("10.0.0.247:27018")
db.runCommand( { listshards : 1 } )
exit
EOF