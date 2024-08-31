#!/bin/bash

# Move Nextcloud into maintenance mode
docker-compose -f ~/nextcloud/docker-compose.yml exec -T -u www-data nextcloud php occ maintenance:mode --on
