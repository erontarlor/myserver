#!/bin/bash

# Move Nextcloud back into normal mode
docker-compose -f ~/nextcloud/docker-compose.yml exec -T -u www-data nextcloud php occ maintenance:mode --off
