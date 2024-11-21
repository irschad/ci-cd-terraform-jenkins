#!/usr/bin/env/ bash

export IMAGE_TAG=$1
export DOCKER_USER=$2
export DOCKER_PWD=$3 
echo $DOCKER_PWD | docker login -u $DOCKER_USER --password-stdin 
docker-compose -f docker-compose.yaml up -d
echo "Successfully started the containers using docker-compose"