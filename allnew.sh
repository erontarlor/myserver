#!/bin/bash

# Redo setting up the server without deleting data.
# Use real certificates.
# If version number is specified as first command line argument, install this version of Nextcloud.
docker-compose -f ~/nextcloud/docker-compose.yml kill
docker-compose -f ~/nextcloud/docker-compose.yml rm -f
curl https://github.com/erontarlor/myserver/raw/master/setup.sh --output ~/setup.sh --location
chmod u+x ~/setup.sh
if [ "$1" != "" ]; then
  sed -i -e "s/image: nextcloud/image: nextcloud:$1/" ~/setup.sh
fi
~/setup.sh -auto
