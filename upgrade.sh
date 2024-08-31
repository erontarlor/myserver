#!/bin/bash

# Start Nextcloud update
docker-compose -f ~/nextcloud/docker-compose.yml exec -u www-data nextcloud php occ upgrade
docker-compose -f ~/nextcloud/docker-compose.yml exec -u www-data nextcloud php occ maintenance:mode --off
