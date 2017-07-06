# CentOS with SSH Docker Image #

## Overview ##

A base image tailored for ClusterControl usage. It automatically configures passwordless SSH from ClusterControl container during startup, allowing ClusterControl to control/manage/deploy database instances seamlessly.

## Image Description ##

To get the image, simply:

```bash
$ docker pull severalnines/centos-ssh
```

The image consists of:
* CentOS 6 base image
* OpenSSH client & server packages
* curl
* mysql client

## Run Container ##

**Requirement**
* ClusterControl container is already started and running.

Once the requirement is satisfied, to run the container, the simplest command would be:

```bash
$ docker run -d \
--link clustercontrol:clustercontrol \
-e AUTO_DEPLOYMENT=0 \
severalnines/centos-ssh
```

More under [Examples](#Examples) further down.

## Build the Image ##

To build the image, download the repository at [our Github repository](https://github.com/severalnines/docker-centos-ssh):

```bash
$ git clone https://github.com/severalnines/docker-centos-ssh
$ cd docker-centos-ssh
$ docker build --rm -t severalnines/centos-ssh .
```

## Environment Variables ##

* `CC_HOST={string}`
	- The value of ClusterControl instance in IP address, hostname or service name format. This container will try to connect to `CC_HOST` port 80 using `curl` to download the SSH key and register itself to CMON database if `AUTO_DEPLOYMENT` is on via mysql client.
	- If undefined, it will try to resolve 'clustercontrol' and 'cc_clustercontrol' naming or look for the value of `$CLUSTERCONTROL_PORT_80_TCP_ADDR`. Thus, linking through `--link` is also supported.
	- Example: `CC_HOST=10.10.10.14`

* `AUTO_DEPLOYMENT={boolean integer}`
	- Default to 1 (enabled). If set to 0, this container will only set up passwordless SSH by downloading the public key from `CC_HOST` and skip registering it in the CMON database. Without this registration, ClusterControl won't be able to "see" the container for automatic deployment.
	- If automatic deployment is disabled, the following environment variables are ignored: `CLUSTER_NAME, CLUSTER_TYPE, INITIAL_CLUSTER_SIZE, VENDOR, PROVIDER_VERSION, DB_ROOT_PASSWORD`
	- Example: `AUTO_DEPLOYMENT=0`

* `CMON_PASSWORD={string}`
	- MySQL password for user 'cmon'. Default to 'cmon'. This value will be used to register the container into CMON database via mysql client.
	- Example: `CMON_PASSWORD=cmonP4s5`

* `CLUSTER_NAME={string}`
	- This name distinguishes the cluster with others from ClusterControl perspective. No space allowed and it must be unique.
	- Example: `CLUSTER_NAME=My_Super_Cluster_on_Docker`

* `CLUSTER_TYPE={string}`
	- Type of supported cluster that ClusterControl would deploy on this container. Supported values are `galera` and `replication` (experimental).
	- Example: `CLUSTER_TYPE=galera`

* `INITIAL_CLUSTER_SIZE={integer}`
	- Default is 3. This indicates how ClusterControl should treat newly registered containers, whether they are for new deployments or for scaling out. For example, if the value is 3, ClusterControl will wait for 3 containers to be running and registered into the CMON database before starting the cluster deployment job. Otherwise, it waits 30 seconds for the next cycle and retries. The next containers (4th, 5th and Nth) will fall under the "Add Node" job instead.
	- Example: `INITIAL_CLUSTER_SIZE=5`

* `VENDOR={string}`
	- Database vendor to use. Default is `percona`. Other supported values are `mariadb`, `codership` and `oracle`.
	- Example: `VENDOR=mariadb`

* `PROVIDER_VERSION={string}`
	- Default is 5.7. The database version by the chosen vendor. For MariaDB, please specify 5.5 or 10.x.
	- Example: `PROVIDER_VERSION=10.1`

* `DB_ROOT_PASSWORD={string}`
	- Mandatory. The database root password for the database server. In this case, it should be MySQL root password.
	- Example: `DB_ROOT_PASSWORD=MyS3cr3t`

## Examples ##

### Automatic Deployment ###

Only Galera cluster is supported in automatic deployment at the moment. We are going to support more clusters in the near future. The following shows how we can deploy a Galera Cluster automatically, which means you only need to execute the 'docker run' commands and wait until the deployment completes.

1) Run the ClusterControl container:
```bash
docker run -d --name clustercontrol -p 5000:80 severalnines/clustercontrol
```

2) Run the DB containers (`CC_HOST` is the ClusterControl container's IP):
```bash
# find the ClusterControl container's IP address
CC_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clustercontrol)
docker run -d --name galera1 -p 6661:3306 -e CC_HOST=${CC_IP} -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
docker run -d --name galera2 -p 6662:3306 -e CC_HOST=${CC_IP} -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
docker run -d --name galera3 -p 6663:3306 -e CC_HOST=${CC_IP} -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
```

Container linking is also supported (assume the ClusterControl container name is 'clustercontrol'):
```bash
docker run -d --name galera1 -p 6661:3306 --link clustercontrol:clustercontrol -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
docker run -d --name galera2 -p 6662:3306 --link clustercontrol:clustercontrol -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
docker run -d --name galera3 -p 6663:3306 --link clustercontrol:clustercontrol -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
```

In Docker Swarm mode, `centos-ssh` will default to look for 'cc_clustercontrol' as the `CC_HOST`. If you create the ClusterControl container with 'cc_clustercontrol' as the service name, you can skip defining `CC_HOST`.

3) Log into ClusterControl UI at http://{docker-host}:5000/clustercontrol to monitor the deployment progress under *Activity -> Jobs*.

4) To scale up, just run new containers and ClusterControl will add them into the cluster automatically:

```bash
docker run -d --name galera4 -p 6664:3306 --link clustercontrol:clustercontrol -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
docker run -d --name galera5 -p 6665:3306 --link clustercontrol:clustercontrol -e CLUSTER_TYPE=galera -e CLUSTER_NAME=mygalera -e INITIAL_CLUSTER_SIZE=3 severalnines/centos-ssh
```

### Manual Deployment ###

Manual deployment allows user to have better control on the deployment process initiates by ClusterControl. All supported database cluster can be deployed using this method. The following shows deployment of 4-node MySQL Replication (1 master + 3 slaves) with 1-node ProxySQL instance on a standalone Docker.

1) Run the ClusterControl container:
```bash
docker run -d --name clustercontrol -p 5000:80 severalnines/clustercontrol
```

2) Run the DB containers (assume the ClusterControl container name is 'clustercontrol'):

```bash
docker run -d --name=master -v /storage/master/datadir:/var/lib/mysql -p 6000:3306 --link clustercontrol:clustercontrol -e AUTO_DEPLOYMENT=0 severalnines/centos-ssh
docker run -d --name=slave1 -v /storage/slave1/datadir:/var/lib/mysql -p 6001:3306 --link clustercontrol:clustercontrol -e AUTO_DEPLOYMENT=0 severalnines/centos-ssh
docker run -d --name=slave2 -v /storage/slave2/datadir:/var/lib/mysql -p 6002:3306 --link clustercontrol:clustercontrol -e AUTO_DEPLOYMENT=0 severalnines/centos-ssh
docker run -d --name=slave3 -v /storage/slave3/datadir:/var/lib/mysql -p 6003:3306 --link clustercontrol:clustercontrol -e AUTO_DEPLOYMENT=0 severalnines/centos-ssh
```

3) Log into ClusterControl UI at http://{docker-host}:5000/clustercontrol and go to *Deploy -> Deploy Database Cluster* and go under MySQL Replication tab. Specify the following:

* SSH User: root
* SSH Key Path: /root/.ssh/id_rsa
* SSH port: 22
* Cluster Name: {Your cluster name}
-- click Continue --

* Vendor: Oracle
* Root Password: {Your MySQL root password}
-- click Continue --

* Master A - IP/Hostname: {Enter master's container IP address. Use 'docker inspect' or look into 'docker logs master | grep CONTAINER_IP'}
* Slave 1: {Enter slave1's container IP address. Use 'docker inspect' or look into 'docker logs slave1 | grep CONTAINER_IP'}
* Slave 2: {Enter slave2's container IP address. Use 'docker inspect' or look into 'docker logs slave2 | grep CONTAINER_IP'}
* Slave 3: {Enter slave3's container IP address. Use 'docker inspect' or look into 'docker logs slave3 | grep CONTAINER_IP'}
-- Click Deploy --

Wait for a couple of minutes until the deployment succeeds. Once done, you will have a MySQL replication cluster consists of 1 master, and 3 slaves.

4) If you would like to have a load balancer in between, you can then create another base container for this purpose. To deploy a ProxySQL using ClusterControl, one would do:

```bash
$ docker run -d --name proxysql1 -p 7001:6033 --link clustercontrol:clustercontrol -e AUTO_DEPLOYMENT=0 severalnines/centos-ssh
```

Then go to *ClusterControl -> choose the cluster -> Add Load Balancer -> ProxySQL*. Enter the required information:

* Server Address: {Enter proxysql1's container IP address. Use 'docker inspect' or look into 'docker logs proxysql1 | grep CONTAINER_IP'
* Administration Password: {Your password}
* Monitor Password: {Your password}
* Create new DB User: {ClusterControl will create this user if it doesn't exist in the MySQL server}
* Select instances to balance: Pick all
* Implicit Transactions: Yes/No (depending on how your application initiates a transaction)
-- click Deploy ProxySQL --

To scale down, you can just simply remove the node from ClusterControl (under Nodes tab), and then remove the container from Docker via `docker rm` command.


## Development ##

Please report bugs, improvements or suggestions via our support channel: [https://support.severalnines.com](https://support.severalnines.com)

If you have any questions, you are welcome to get in touch via our [contact us](http://www.severalnines.com/contact-us) page or email us at info@severalnines.com.
