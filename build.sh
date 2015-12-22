#!/bin/bash

PORT=8000
INSTANCE=my_nginx
IMAGE=procrastinatio/varnish-config-test
url=http://localhost:${PORT}


DIR=$HOME/droneio


TAG=$(date +%s)

sudo docker kill ${INSTANCE}  && sudo docker rm ${INSTANCE}



sudo docker build -t ${IMAGE}:${TAG} .


sudo docker run --name ${INSTANCE}  -p ${PORT}:80  -d ${IMAGE}:${TAG}

status=$(curl --write-out %{http_code} --silent --output /dev/null "${url}/")

echo ${status}

[ ${status} -eq 200 ]   && sudo docker push ${IMAGE}:${TAG}  && sudo docker rm  ${IMAGE}:${TAG}

