#!/bin/bash

# Destroy all docker containers and volumes
docker-compose -f ~/nextcloud/docker-compose.yml kill
docker-compose -f ~/nextcloud/docker-compose.yml rm -f
for i in `docker volume list -q`; do
  docker volume rm $i
done
