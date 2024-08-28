#!/bin/bash

docker-compose -f ~/nextcloud/docker-compose.yml kill
docker-compose -f ~/nextcloud/docker-compose.yml rm -f
curl https://github.com/erontarlor/myserver/raw/master/setup.sh --output ~/setup.sh --location
chmod u+x ~/setup.sh
~/setup.sh -auto -testcertificates
