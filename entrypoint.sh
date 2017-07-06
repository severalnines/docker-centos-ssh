#!/bin/bash

if [ ! -z "$AUTO_DEPLOYMENT" ]; then
	if [ "$AUTO_DEPLOYMENT" -eq 1 ]; then
		AUTO_DEPLOY=1
		echo
		echo -e ">> AUTO_DEPLOYMENT is 1. Automatic deployment is enabled."
	else
		AUTO_DEPLOY=0
	fi
else
	AUTO_DEPLOY=1
	echo
	echo -e ">> AUTO_DEPLOYMENT is undefined. Using the default value: 1"
fi

if [ $AUTO_DEPLOY -eq 1 ]; then

	if [ -z "$CLUSTER_NAME" ]; then
		echo
		echo -e ">> CLUSTER_NAME is required. Example: '-e CLUSTER_NAME=galera1'"
		echo -e ">> Use different name for different service. No whitespace allowed."
		exit 1
	fi

	if [ -z "$CLUSTER_TYPE" ]; then
		echo 
		echo -e ">> CLUSTER_TYPE is required. Example: -e CLUSTER_TYPE=galera"
		echo -e ">> Supported values are galera, replication, mongodb"
		exit 1
	fi

	if [ -z "$INITIAL_CLUSTER_SIZE" ]; then
		echo 
		echo -e ">> INITIAL_CLUSTER_SIZE is required. Example -e INITIAL_CLUSTER_SIZE=3"
		echo -e ">> This value tells ClusterControl the cluster size during initial deployment."
		echo -e ">> If the number of containers is higher, only the first INITIAL_CLUSTER_SIZE container will be deployed,"
		echo -e ">> the rest will be scaled accordingly by adding it into this cluster."
		exit 1
	fi

	if [ -z "$VENDOR" ]; then
		echo -e ">> VENDOR is undefined. Using the default vendor: 'percona'"
		VENDOR=percona
	fi

	if [ -z "$PROVIDER_VERSION" ]; then
		echo -e ">> PROVIDER_VERSION is undefined. Using the default version: '5.7'"
		PROVIDER_VERSION=5.7
	fi

	if [ -z "$DB_ROOT_PASSWORD" ]; then
		echo -e ">> DB_ROOT_PASSWORD is undefined. Using the default password: 'password'"
		DB_ROOT_PASSWORD=password
	fi
else
	echo
	echo -e ">> AUTO_DEPLOYMENT is not 1. Automatic deployment is disabled."
	echo -e ">> The following variables are ignored if specified:"
	echo -e ">> CLUSTER_NAME, CLUSTER_TYPE, INITIAL_CLUSTER_SIZE, VENDOR, PROVIDER_VERSION, DB_ROOT_PASSWORD."

fi

if [ -z "$CMON_PASSWORD" ]; then
        echo -e ">> CMON_PASSWORD is undefined. Using the default password: 'cmon'"
        CMON_PASSWORD=cmon
fi

test_cc_host() {
	local host=$1
	curl -sSf http://$host/clustercontrol/ > /dev/null
	[ $? -eq 0 ] && return 0 || return 1
}

if [ ! -z "$CLUSTERCONTROL_PORT_80_TCP_ADDR" ]; then
        CC_HOST=$CLUSTERCONTROL_PORT_80_TCP_ADDR
	echo
        echo ">> Linking exists. Using CC_HOST=${CC_HOST}"
	test_cc_host $CC_HOST
	if [ $? -ne 0 ]; then
		echo -e ">> Couldn't reach ${CC_HOST}. Ensure ClusterControl is installed and reachable."
		CC_HOST=
	fi
fi

if [ -z "$CC_HOST" ]; then
	echo 
	echo -e ">> CC_HOST is undefined. Trying to connect using default hostname, 'clustercontrol'"
	test_cc_host clustercontrol
	if [ $? -ne 0 ]; then
		echo -e ">> Couldn't reach host 'clustercontrol'"
        	echo -e ">> CC_HOST is required. Example: '-e CC_HOST=192.168.10.111'"
	        echo -e ">> If you are on Swarm/Kubernetes, use ClusterControl's virtual IP address instead."
       		exit 1
	else
		CC_HOST=clustercontrol
		echo -e ">> 'clustercontrol' is reachable. Using CC_HOST=${CC_HOST}"
	fi
fi

HOST=$(echo $CC_HOST | cut -f 1 -d ':')
HTTP_PUB_KEY="http://${HOST}/keys/cc.pub"
AUTHORIZED_DIR=/root/.ssh
AUTHORIZED_KEYS=$AUTHORIZED_DIR/authorized_keys
TMP_KEY=/tmp/key.pub
FLAG_FILE=/root/registered_with_cc

if [ ! -e $FLAG_FILE ]; then
	echo
	echo -e ">> Retrieving public key from ClusterControl container"
	curl -s $HTTP_PUB_KEY >> $TMP_KEY
	if [ $? -eq 0 ]; then
		echo
		echo -e ">> Setting up authorized_keys"
		[ -d $AUTHORIZED_DIR ] || mkdir -p $AUTHORIZED_DIR
		touch $AUTHORIZED_KEYS
		if [ -s $TMP_KEY ]; then
			cat $TMP_KEY >> $AUTHORIZED_KEYS
			chmod 600 $AUTHORIZED_KEYS
			chmod 700 $AUTHORIZED_DIR
		else
			echo -e ">> Retrieved public key is empty. Exiting."
			exit 1
		fi
		rm -f $TMP_KEY
	else
		echo -e ">> Unable to retrieve public key from ClusterControl container. Exiting."
		exit 1
	fi

	HOSTNAME=$(hostname)
	IP_ADDRESS=$(ip a | grep eth0 | grep inet | awk {'print $2'} | cut -d '/' -f 1 | head -1)
	[ -z $IP_ADDRESS ] && IP_ADDRESS=$(hostname -i | awk {'print $1'})

	# TODO: insert into 'cmon.containers' table manually. should be done by RPC

	echo
	echo "============================"
	echo "Loaded environment variables"
	echo "============================"
	echo "HOSTNAME             : $HOSTNAME"
	echo "CONTAINER_IP         : $IP_ADDRESS"
	echo "CLUSTER_TYPE         : $CLUSTER_TYPE"
	echo "CLUSTER_NAME         : $CLUSTER_NAME"
	echo "VENDOR               : $VENDOR"
	echo "PROVIDER_VERSION     : $PROVIDER_VERSION"
	echo "INITIAL_CLUSTER_SIZE : $INITIAL_CLUSTER_SIZE"
	echo "AUTO_DEPLOYMENT      : $AUTO_DEPLOY"

	if [ $AUTO_DEPLOY -eq 1 ]; then
        	echo
	        echo -e ">> Registering this container with ClusterControl, ${HOST} for automatic deployment"
		/usr/bin/mysql -ucmon -p${CMON_PASSWORD} -h${HOST} -e \
		"INSERT INTO cmon.containers (hostname,ip,cluster_type,cluster_name,vendor,provider_version,db_root_password,initial_size,created) VALUES ('$HOSTNAME','$IP_ADDRESS','$CLUSTER_TYPE','$CLUSTER_NAME', '$VENDOR', '$PROVIDER_VERSION', '$DB_ROOT_PASSWORD', $INITIAL_CLUSTER_SIZE, 1)"
		[ $? -eq 0 ] && touch $FLAG_FILE
	else
		echo 
		echo -e ">> Skipping registering this container for automatic deployment"
	fi
	
	[ -d /var/run/sshd ] ||  mkdir /var/run/sshd
	[ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ''
	[ -f /etc/ssh/ssh_host_dsa_key ] || ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N ''
fi

echo
echo ">> Starting SSHD in the background"
/usr/sbin/sshd -D
