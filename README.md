# Mobile Demo Container 2.0.4

Container to run the Sync Gateway and Couchbase Server components for the Couchbase Mobile [Android Demo](https://github.com/mminichino/sgw-android-example).

Download the helper script:

````
curl -L -O https://github.com/mminichino/mobile-demo-container/releases/download/2.0.4/rundemo.sh
````

Run the container:

````
./rundemo.sh --run
````

Watch the container console output:

````
./rundemo.sh --tail
````

Stop the container:
````
./rundemo.sh --stop
````

Docker command to run the container:
````
docker run -d --name mobiledemo \
                -p 8091:8091 \
                -p 8092:8092 \
                -p 8093:8093 \
                -p 8094:8094 \
                -p 8095:8095 \
                -p 8096:8096 \
                -p 8097:8097 \
                -p 11210:11210 \
                -p 9102:9102 \
                -p 4984:4984 \
                -p 4985:4985 \
                -p 8080:8080 \
                -p 8081:8081 \
                mminichino/mobiledemo
````
