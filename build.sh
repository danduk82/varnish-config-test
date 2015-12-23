#!/bin/bash

PORT=80
INSTANCE=my_varnish
IMAGE=procrastinatio/varnish-config-test
url=http://localhost:${PORT}

TAG=$(date +%s)

sudo docker build -t ${IMAGE}:${TAG} .

sudo docker run --name ${INSTANCE}  -p ${PORT}:80  -d ${IMAGE}:${TAG}

nose2
[ $? -eq  0 ]   && sudo docker push ${IMAGE}:${TAG}  && sudo docker kill ${INSTANCE}  && sudo docker rm ${INSTANCE}

