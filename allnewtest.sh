#!/bin/bash

cd ~/nextcloud
docker-compose kill
docker-compose rm
cd ~
curl https://github.com/erontarlor/myserver/raw/master/setup.sh --output setup.sh --location
chmod u+x setup.sh
~/setup.sh -auto -testcertificates
