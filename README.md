# myserver
Linux BASH script for setting up a private web server with pre-configured ownCloud service and automatically renewing Let's Encrypt SSL certificates, based on a basic Ubuntu 18.04 cloud server with root access, using docker images.

(c) 2018 by erontarlor

## Prerequisites
- Cloud server with root permissions (tested with 1&1 Cloud, but likely will work with other providers)
- Minimal Ubuntu OS installed (tested with Ubuntu 18.04, but likely will work with other Ubuntu based distributions and versions)
- SSH access to the cloud server

## Installation
Either login to your cloud server as *root* and download the script `setup.sh` from GitHub directly onto the cloud server (if `curl` is already installed there):

    ssh -l root yourserver
    curl https://github.com/erontarlor/myserver/blob/master/setup.sh

Or download the script locally, copy it to your cloud server via `scp` and login to the server afterwards:

    curl https://github.com/erontarlor/myserver/blob/master/setup.sh
    scp setup.sh root@yourserver:/root/setup.sh
    ssh -l root yourserver

Make sure, the script `setup.sh` has execute permission:

    chmod +x setup.sh

Run script as *root* and interactively answer all the questions about the desired configuration:

    ./setup.sh

After setting up your server has finished, your entered data will be stored in a file called `setup.cfg` within the current directory. Since this file also contains the entered passwords, it is only readable by the user *root*.

You can use this file later on, to re-run the setup. The script will then use the previously entered data as defaults for all the questions. Just hit \[ENTER\] to use the defaults.

Yout can also re-run the setup in auto mode, without entering all data again:

    ./setup.sh -auto

There is also a debug mode, listing all the setup steps but performing no changes:

    ./setup.sh -debug

In default, the script tries to install and setup SSL access, using free Let's Encrypt SSL certificates. If you want to use your own certificates, you can setup the system, using self-signed certificates:

    ./setup.sh -testcertificates

You can then replace the certificate files by your own ones later on. They can be found here:

    /etc/ssl/certs/yourdomain.pem
    /etc/ssl/private/yourdomain.key 

# Installed features
After setup has completed, the server should be accessable from the internet via a browser:

    https://yourdomain

And via `ssh` using the new port you have specified:

    ssh -p yourport -l root yourdomain

The server should contain the following features:
- Changed root password
- Added one or more additional operating system users (at least one with sudo rights)
- Some additionally installed basic tools like `gvim`, `curl`, ...
- Installed Docker environment with `docker-compose`
- Installed ownCloud docker container with many pre-installed apps, the same users as for the OS and an *admin* user with the specified admin password
- Installed supporting docker containers (mysql, redis)
- Created docker volumes for permanently storing data (accessable from outside the containers):
    - `owncloud_backup`: `/var/lib/docker/volumes/owncloud_backup/_data`
    - `owncloud_files`: `/var/lib/docker/volumes/owncloud_files/_data`
    - `owncloud_mysql`: `/var/lib/docker/volumes/owncloud_mysql/_data`
    - `owncloud_redis`: `/var/lib/docker/volumes/owncloud_redis/_data`
- Installed Let's Encrypt environment with cron job for automatically renewing the certificates
- Configured Apache web server as proxy for redirecting the incoming https requests to the different docker containers
- Disabled root login for SSH
- Changed port for SSH


Have fun.
