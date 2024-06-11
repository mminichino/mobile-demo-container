#!/bin/bash
set -e

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

echo "Configuring Couchbase Server"
swmgr cluster create -n testdb
echo "Starting Sync Gateway"
swmgr gateway configure -T
bundlemgr -b StartSGW

swmgr cluster wait -n testdb
swmgr gateway wait -T

cd /demo/couchbase

# Load the adjuster schema
echo "Loading insurance_sample demo schema"
cbcutil load --host 127.0.0.1 --schema insurance_sample --replica 0 --safe --quota 128
# Load the employee schema
echo "Loading timecard_sample demo schema"
cbcutil load --host 127.0.0.1 --schema timecard_sample --replica 0 --safe --quota 128

if [ $? -ne 0 ]; then
  echo "Schema configuration error"
  exit 1
fi

# Configure the Sync Gateway
if [ ! -f /demo/couchbase/.sgwconfigured ]; then
  echo "Creating Sync Gateway insurance database"
  sgwutil database create -s -h 127.0.0.1 -b insurance_sample -k insurance_sample.data -n insurance
  echo "Creating Sync Gateway timecard database"
  sgwutil database create -s -h 127.0.0.1 -b timecard_sample -k timecard_sample.data -n timecard

  echo "Waiting for the databases to become available"
  sgwutil database wait -s -h 127.0.0.1 -n insurance
  sgwutil database wait -s -h 127.0.0.1 -n timecard

  if [ $? -ne 0 ]; then
    echo "Sync Gateway database creation error"
    exit 1
  fi

  echo "Creating Sync Gateway insurance users"
  sgwutil user map -s -h 127.0.0.1 -d 127.0.0.1 -F region -k insurance_sample -n insurance
  echo "Creating Sync Gateway timecard users"
  sgwutil user map -s -h 127.0.0.1 -d 127.0.0.1 -F location_id -k timecard_sample -n timecard

  echo "Adding adjuster sync function to insurance database"
  sgwutil database sync -s -h 127.0.0.1 -n insurance -f /etc/sync_gateway/insurance.js
  echo "Adding employee sync function to timecard database"
  sgwutil database sync -s -h 127.0.0.1 -n timecard -f /etc/sync_gateway/timecard.js

  if [ $? -ne 0 ]; then
    echo "Sync Gateway configuration error"
    exit 1
  fi
else
  echo "Sync Gateway already configured."
fi

touch /demo/couchbase/.sgwconfigured

# Configuration complete

while true; do
  if [ -f /home/sync_gateway/logs/sg_info.log ]; then
    break
  fi
  sleep 1
done

export NVM_DIR=/usr/local/nvm
. $NVM_DIR/nvm.sh
cd /demo/couchbase/microservice

echo "Starting auth microservices"
pm2 start /demo/couchbase/config/auth-svc-ssl.json

echo "Container is now ready"
echo "The following output is now a tail of sg_info.log:"
tail -f /home/sync_gateway/logs/sg_info.log &
childPID=$!
wait $childPID
