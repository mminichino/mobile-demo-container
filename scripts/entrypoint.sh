#!/bin/bash
USE_SSL=0
PRINT_USAGE="Usage: $0 [ -s ]
             -s Use SSL for Sync Gateway"
set -e

function print_usage {
if [ -n "$PRINT_USAGE" ]; then
   echo "$PRINT_USAGE"
fi
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

while getopts "s" opt
do
  case $opt in
    s)
      USE_SSL=1
      ;;
    \?)
      print_usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

staticConfigFile=/opt/couchbase/etc/couchbase/static_config
restPortValue=8091

# see https://developer.couchbase.com/documentation/server/current/install/install-ports.html
function overridePort() {
    portName=$1
    portNameUpper=$(echo $portName | awk '{print toupper($0)}')
    portValue=${!portNameUpper}

    # only override port if value available AND not already contained in static_config
    if [ "$portValue" != "" ]; then
        if grep -Fq "{${portName}," ${staticConfigFile}
        then
            echo "Don't override port ${portName} because already available in $staticConfigFile"
        else
            echo "Override port '$portName' with value '$portValue'"
            echo "{$portName, $portValue}." >> ${staticConfigFile}

            if [ ${portName} == "rest_port" ]; then
                restPortValue=${portValue}
            fi
        fi
    fi
}

overridePort "rest_port"
overridePort "mccouch_port"
overridePort "memcached_port"
overridePort "query_port"
overridePort "ssl_query_port"
overridePort "fts_http_port"
overridePort "moxi_port"
overridePort "ssl_rest_port"
overridePort "ssl_capi_port"
overridePort "ssl_proxy_downstream_port"
overridePort "ssl_proxy_upstream_port"

if [ "$(whoami)" = "couchbase" ]; then
    # Ensure that /opt/couchbase/var is owned by user 'couchbase' and
    # is writable
    if [ ! -w /opt/couchbase/var -o \
        $(find /opt/couchbase/var -maxdepth 0 -printf '%u') != "couchbase" ]; then
        echo "/opt/couchbase/var is not owned and writable by UID 1000"
        echo "Aborting as Couchbase Server will likely not run"
        exit 1
    fi
fi

if [ -e /etc/service/git-daemon ]; then
  rm /etc/service/git-daemon
fi

# Start Couchbase Server
echo "Starting Couchbase Server -- Web UI available at http://<ip>:$restPortValue"
echo "and logs available in /opt/couchbase/var/lib/couchbase/logs"
runsvdir -P /etc/service 'log: ...........................................................................................................................................................................................................................................................................................................................................................................................................' &

# Start Sync Gateway
if [ "$USE_SSL" -eq 0 ]; then
  EXTRA_ARGS=""
  echo "Starting Sync Gateway"
  /opt/couchbase-sync-gateway/bin/sync_gateway --defaultLogFilePath=/demo/couchbase/logs /etc/sync_gateway/config.json &
else
  EXTRA_ARGS="--ssl"
  echo "Creating Certificates"
  openssl genrsa -out /etc/sync_gateway/privkey.pem 2048
  openssl req -new -x509 -sha256 \
  -key /etc/sync_gateway/privkey.pem \
  -out /etc/sync_gateway/cert.pem \
  -days 3650 \
  -subj '/C=US/ST=California/L=Santa Clara/O=Couchbase'
  [ ! -f /etc/sync_gateway/privkey.pem ] || [ ! -f /etc/sync_gateway/cert.pem ] && err_exit "Can not create certificates"
  echo "Starting Sync Gateway (SSL)"
  /opt/couchbase-sync-gateway/bin/sync_gateway --defaultLogFilePath=/demo/couchbase/logs /etc/sync_gateway/config_ssl.json &
fi
echo $! > /etc/sync_gateway/run.pid

# Wait for CBS to start
echo -n "Waiting for Couchbase Server to start ... "
while true; do
  if /opt/couchbase/bin/couchbase-cli host-list \
  --cluster 127.0.0.1 \
  --username Administrator \
  --password "password" | \
  grep -q "Unable to connect"; then
    sleep 1
  else
    break
  fi
done
echo "done."

# Configuration section
echo "Configuring Couchbase Cluster"

# Initialize the node
if /opt/couchbase/bin/couchbase-cli host-list \
  --cluster 127.0.0.1 \
  --username Administrator \
  --password "password" | \
  grep -q "127.0.0.1"; then
    echo "This node already exists in the cluster"
else
/opt/couchbase/bin/couchbase-cli node-init \
  --cluster 127.0.0.1 \
  --username Administrator \
  --password "password" \
  --node-init-hostname 127.0.0.1 \
  --node-init-data-path /opt/couchbase/var/lib/couchbase/data \
  --node-init-index-path /opt/couchbase/var/lib/couchbase/data \
  --node-init-analytics-path /opt/couchbase/var/lib/couchbase/data \
  --node-init-eventing-path /opt/couchbase/var/lib/couchbase/data
fi

# Initialize the single node cluster
if /opt/couchbase/bin/couchbase-cli setting-cluster \
  --cluster 127.0.0.1 \
  --username Administrator \
  --password "password" | \
  grep -q 'ERROR: Cluster is not initialized'; then
/opt/couchbase/bin/couchbase-cli cluster-init \
  --cluster 127.0.0.1 \
  --cluster-username Administrator \
  --cluster-password "password" \
  --cluster-port 8091 \
  --cluster-ramsize 512 \
  --cluster-fts-ramsize 512 \
  --cluster-index-ramsize 256 \
  --cluster-eventing-ramsize 256 \
  --cluster-analytics-ramsize 1024 \
  --cluster-name empdemo \
  --index-storage-setting default \
  --services "data,index,query"
else
  echo "This node is already initialized"
fi

cd /demo/couchbase/cbperf

# Wait for the cluster to initialize and for all services to start
set +e
while true; do
  sleep 1
  bin/cb_perf list --host 127.0.0.1 --wait 2>&1
  [ $? -ne 0 ] && continue
  break
done

# Load the adjuster schema
echo "Loading insurance_sample demo schema"
bin/cb_perf load --host 127.0.0.1 --schema insurance_sample --replica 0 --safe --quota 128
# Load the employee schema
echo "Loading timecard_sample demo schema"
bin/cb_perf load --host 127.0.0.1 --schema timecard_sample --replica 0 --safe --quota 128

if [ $? -ne 0 ]; then
  echo "Schema configuration error"
  exit 1
fi

cd /demo/couchbase/sgwcli

# Configure the Sync Gateway
if [ ! -f /demo/couchbase/.sgwconfigured ]; then
  echo "Creating Sync Gateway insurance database"
  ./sgwcli database create -h 127.0.0.1 -b insurance_sample -k insurance_sample.data -n insurance $EXTRA_ARGS
  echo "Creating Sync Gateway timecard database"
  ./sgwcli database create -h 127.0.0.1 -b timecard_sample -k timecard_sample.data -n timecard $EXTRA_ARGS

  echo "Waiting for the databases to become available"
  ./sgwcli database wait -h 127.0.0.1 -n insurance $EXTRA_ARGS
  ./sgwcli database wait -h 127.0.0.1 -n timecard $EXTRA_ARGS

  if [ $? -ne 0 ]; then
    echo "Sync Gateway database creation error"
    exit 1
  fi

  echo "Creating Sync Gateway insurance users"
  ./sgwcli user map -h 127.0.0.1 -d 127.0.0.1 -f region -k insurance_sample -n insurance $EXTRA_ARGS
  echo "Creating Sync Gateway timecard users"
  ./sgwcli user map -h 127.0.0.1 -d 127.0.0.1 -f location_id -k timecard_sample -n timecard $EXTRA_ARGS

  echo "Adding adjuster sync function to insurance database"
  ./sgwcli database sync -h 127.0.0.1 -n insurance -f /etc/sync_gateway/insurance.js $EXTRA_ARGS
  echo "Adding employee sync function to timecard database"
  ./sgwcli database sync -h 127.0.0.1 -n timecard -f /etc/sync_gateway/timecard.js $EXTRA_ARGS

  if [ $? -ne 0 ]; then
    echo "Sync Gateway configuration error"
    exit 1
  fi
else
  echo "Sync Gateway already configured."
fi

cd /demo/couchbase
touch /demo/couchbase/.sgwconfigured

# Configuration complete

while true; do
  if [ -f /demo/couchbase/logs/sg_info.log ]; then
    break
  fi
  sleep 1
done

export NVM_DIR=/usr/local/nvm
. $NVM_DIR/nvm.sh
cd /demo/couchbase/microservice
if [ "$USE_SSL" -eq 0 ]; then
  echo "Starting auth microservices"
  pm2 start /demo/couchbase/config/auth-svc.json
else
  echo "Starting auth microservices (SSL)"
  pm2 start /demo/couchbase/config/auth-svc-ssl.json
fi

echo "Container is now ready"
echo "The following output is now a tail of sg_info.log:"
tail -f /demo/couchbase/logs/sg_info.log &
childPID=$!
wait $childPID
