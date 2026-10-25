#!/bin/bash
#
# setup.sh V0.6
#
# Script for setting up the automatically renewing Let's Encrypt SSL certificates.
#
# (c) 2026 by erontarlor
#

declare -i step=1
declare -i debug=0
declare -i auto=1

declare -i certificateCount=1
declare -a certificateDomain
declare -a certificateCountry
declare -a certificateState
declare -a certificateCity
declare -a certificateOrganization
declare -a certificateEMail
certificateDomain[0]=localhost

declare configFile=setup.cfg
if [ -e "$configFile" ]
then
  source $configFile
fi

getArgs()
{
  for arg in "$@"
  do
    if [ "$arg" = "-debug" ]
    then
      debug=1
    fi
  done
}


call()
{
  if [ "$debug" = 1 ]
  then
    echo "$1"
  else
    eval "$1"
  fi
  if [ $? -gt 0 ]
  then
    exit $?
  fi
}


runStep()
{
  echo "$step. $1"
  if [ ! -z "$2" ]
  then
    shift
    "$@"
  fi
  echo ""
  let step=step+1
}


declare value
askValue()
{
  value=$2
  while [ "$auto" = 1 ] || read -r -p "$1 [$2]: " value
  do
    value="${value:-$2}"
    if [ ! -z "$value" ]
    then
      break
    fi
  done
}


addLetsEncryptRepository()
{
  call "add-apt-repository universe -n -y"
}


installLetsEncrypt()
{
  call "apt install certbot python3-certbot-apache -y"
  declare file="/etc/cron.weekly/letsencrypt"
  call "echo \"#!/bin/sh\" > $file"
  call "echo \"certbot renew\" >> $file"
  call "chmod a+x $file"
}


configureApache()
{
  declare originalSite="/etc/apache2/sites-enabled/000-default.conf"
  if [ -e "$originalSite" ]
  then
    call "rm \"$originalSite\""
  fi
  call "a2enmod proxy"
  call "a2enmod proxy_http"
  call "a2enmod proxy_ajp"
  call "a2enmod rewrite"
  call "a2enmod deflate"
  call "a2enmod headers"
  call "a2enmod proxy_balancer"
  call "a2enmod proxy_connect"
  call "a2enmod proxy_html"
  call "a2enmod socache_shmcb"
  call "a2enmod ssl"
  echo "Adding virtual hosts..."
  declare count=$certificateCount
  while [ "$count" -gt 0 ]
  do
    let count=count-1
    createWebSite $count
  done
}


createWebSite()
{
  declare siteNo=$1
  askValue "Enter domain name" "${certificateDomain[$siteNo]}"
  certificateDomain[$siteNo]=$value
  askValue "Enter country abbreviation" "${certificateCountry[$siteNo]}"
  certificateCountry[$siteNo]=$value
  askValue "Enter state" "${certificateState[$siteNo]}"
  certificateState[$siteNo]=$value
  askValue "Enter city" "${certificateCity[$siteNo]}"
  certificateCity[$siteNo]=$value
  askValue "Enter organization" "${certificateOrganization[$siteNo]}"
  certificateOrganization[$siteNo]=$value
  askValue "Enter NextCloud user responsible for the web site" "${certificateUser[$siteNo]}"
  certificateUser[$siteNo]=$value
  askValue "Enter e-mail" "${certificateEMail[$siteNo]}"
  certificateEMail[$siteNo]=$value
  askValue "Enter 0 if this site is private or 1 if it is public" "${certificatePublic[$siteNo]}"
  certificatePublic[$siteNo]=$value
  declare serverName=${certificateDomain[$siteNo]}
  declare rootDir=/var/www/html/$serverName
  call "mkdir -p $rootDir"
  declare file=/etc/apache2/sites-available/$serverName.conf
  createWebSiteConfig $file $serverName ${certificateUser[$siteNo]} ${certificateEMail[$siteNo]} $rootDir $siteNo ${certificatePublic[$siteNo]}
  createLink $file /etc/apache2/sites-enabled/$serverName.conf
  runCertbotIfNecessary $siteNo
}


createWebSiteConfig()
{
  declare file=$1
  declare serverName=$2
  declare user=$3
  declare eMailAddress=$4
  declare rootDir=$5
  declare siteNo=$6
  declare publicSite=$7
  call "echo \"<IfModule mod_ssl.c>\" > $file"
  call "echo \"<VirtualHost *:80>\" >> $file"
  addSiteDataToConfig $file $serverName $user $eMailAddress $rootDir $siteNo
  call "echo \"<IfModule mod_headers.c>\" >> $file"
  if [ "$publicSite" = 1 ]
  then
    addPublicSiteHeader $file
  fi
  call "echo \"Header always set Strict-Transport-Security \\\"max-age=15552000; includeSubDomains; preload\\\"\" >> $file"
  call "echo \"</IfModule>\" >> $file"
  call "echo \"</VirtualHost>\" >> $file"
  call "echo \"</IfModule>\" >> $file"
}


addSiteDataToConfig()
{
  declare file=$1
  declare serverName=$2
  declare user=$3
  declare eMailAddress=$4
  declare rootDir=$5
  declare siteNo=$6
  call "echo \"ServerName $serverName\" >> $file"
  #call "echo \"ServerAlias www.$serverName\" >> $file"
  call "echo \"ServerAdmin $eMailAddress\" >> $file"
  call "echo \"DocumentRoot $rootDir\" >> $file"
  call "echo 'ErrorLog \${APACHE_LOG_DIR}/$serverName-error.log' >> $file"
  call "echo 'CustomLog \${APACHE_LOG_DIR}/$serverName-access.log combined' >> $file"
  # Possible values include: debug, info, notice, warn, error, crit, alert, emerg.
  call "echo \"LogLevel warn\" >> $file"
  if [ "$siteNo" = 0 ]
  then
    addProxyPassToConfig $file http://localhost:8080
  else
    call "echo \"ErrorDocument 404 /404.html\" >> $file"
    addContentDirectoryToConfig $file $rootDir
    configureHugo $serverName $user $rootDir
  fi
}


addProxyPassToConfig()
{
  declare file=$1
  declare url=$2
  call "echo \"ProxyPass / $url/\" >> $file"
  call "echo \"ProxyPassReverse / $url/\" >> $file"
}


addContentDirectoryToConfig()
{
  declare file=$1
  declare rootDir=$2
  call "echo \"<Directory $rootDir>\" >> $file"
  call "echo \"  Options -Indexes -ExecCGI\" >> $file"
  call "echo \"  AllowOverride None\" >> $file"
  call "echo \"  Require all granted\" >> $file"
  call "echo \"</Directory>\" >> $file"
}


configureHugo()
{
  declare serverName=$1
  declare user=$2
  declare rootDir=$3
  createHugoBuildScript $serverName "/var/lib/docker/volumes/nextcloud_nextcloud/_data/data/$user/files/Websites/$serverName" $rootDir
  createHugoService $serverName
  createHugoTimer $serverName
}


createHugoBuildScript()
{
  declare serverName=$1
  declare srcDir=$2
  declare rootDir=$3
  declare file=/etc/apache2/sites-available/$serverName-hugo.sh
  call "echo '#!/usr/bin/env bash' > $file"
  call "echo 'set -Eeuo pipefail' >> $file"
  call "echo 'if [[ ! -d $srcDir ]]' >> $file"
  call "echo 'then' >> $file"
  call "echo '  echo \"No source files found for web site $serverName - nothing to be done.\"' >> $file"
  call "echo '  exit 0' >> $file"
  call "echo 'fi' >> $file"
  call "echo 'echo \"Checking if web site $serverName needs to be released...\"' >> $file"
  call "echo 'declare changedFiles=\$(find -L \"$srcDir\" -newer \"$rootDir\")' >> $file"
  call "echo 'if [[ \$changedFiles == \"\" ]]' >> $file"
  call "echo 'then' >> $file"
  call "echo '  echo \"Nothing has changed - no release necessary.\"' >> $file"
  call "echo '  exit 0' >> $file"
  call "echo 'fi' >> $file"
  call "echo 'echo \"Files changed:\"' >> $file"
  call "echo 'echo \"\$changedFiles\"' >> $file"
  call "echo 'sleep 3' >> $file"
  call "echo 'echo \"Deleting old temporary directory...\"' >> $file"
  call "echo 'if [[ -f \"$rootDir-new\" ]]' >> $file"
  call "echo 'then' >> $file"
  call "echo '  rm -rf \"$rootDir-new\"' >> $file"
  call "echo 'fi' >> $file"
  call "echo 'echo \"Creating new temporary directory...\"' >> $file"
  call "echo 'mkdir -p \"$rootDir-new\"' >> $file"
  call "echo 'echo \"Running Hugo to create web site...\"' >> $file"
  call "echo 'hugo --source \"$srcDir\" --destination \"$rootDir-new\" --cleanDestinationDir' >> $file"
  call "echo 'test -s \"$rootDir-new/index.html\"' >> $file"
  call "echo 'echo \"Saving currently released directory...\"' >> $file"
  call "echo 'mv \"$rootDir\" \"$rootDir-old\"' >> $file"
  call "echo 'echo \"Releasing new directory...\"' >> $file"
  call "echo 'if mv \"$rootDir-new\" \"$rootDir\"' >> $file"
  call "echo 'then' >> $file"
  call "echo '  echo \"Deleting old directory...\"' >> $file"
  call "echo '  rm -rf \"$rootDir-old\"' >> $file"
  call "echo '  echo \"Done.\"' >> $file"
  call "echo 'else' >> $file"
  call "echo '  echo \"Error releasing new directory - restoring old one...\"' >> $file"
  call "echo '  mv \"$rootDir-old\" \"$rootDir\"' >> $file"
  call "echo 'fi' >> $file"
  call "chmod a+x $file"
}


createHugoService()
{
  declare serverName=$1
  declare file=/etc/systemd/system/$serverName-hugo.service
  call "echo '[Unit]' > $file"
  call "echo 'Description=Build web site for $serverName with Hugo' >> $file"
  call "echo '[Service]' >> $file"
  call "echo 'Type=oneshot' >> $file"
  call "echo 'User=root' >> $file"
  call "echo 'Group=www-data' >> $file"
  call "echo 'ExecStart=/etc/apache2/sites-available/$serverName-hugo.sh' >> $file"
}


createHugoTimer()
{
  declare serverName=$1
  declare file=/etc/systemd/system/$serverName-hugo.timer
  call "echo '[Unit]' > $file"
  call "echo 'Description=Run web site build for $serverName periodically' >> $file"
  call "echo '[Timer]' >> $file"
  call "echo 'OnBootSec=5min' >> $file"
  call "echo 'OnUnitActiveSec=1min' >> $file"
  call "echo 'Unit=$serverName-hugo.service' >> $file"
  call "echo '[Install]' >> $file"
  call "echo 'WantedBy=timers.target' >> $file"
}


addPublicSiteHeader()
{
  declare file=$1
  call "echo \"Header unset X-Robots-Tag\" >> $file"
  call "echo \"Header unset Pragma\" >> $file"
  call "echo \"Header set Cache-Control \\\"public, must-revalidate\\\"\" >> $file"
}


createLink()
{
  if [ ! -e "$2" ]
  then
    call "ln -s \"$1\" \"$2\""
  fi
}


runCertbotIfNecessary()
{
  declare siteNo=$1
  echo "Running Let's Encrypt certbot for domain ${certificateDomain[$siteNo]}..."
  #call "certbot --apache --test-cert --agree-tos -n -d ${certificateDomain[$siteNo]} -m ${certificateEMail[$siteNo]}"
  call "certbot --apache --agree-tos -n -d ${certificateDomain[$siteNo]} -m ${certificateEMail[$siteNo]}"
}


getArgs "$@"
if [ "$debug" = 1 ]
then
  echo "Using debug mode: no changes are done to the system."
fi
echo "Using auto mode: no user interaction, just using same values as last time."
echo "Using SSL certificates from Let's Encrypt."
runStep "Adding Let's Encrypt repository..." addLetsEncryptRepository
runStep "Installing Let's Encrypt..." installLetsEncrypt
runStep "Configuring host's apache web server..." configureApache
runStep "Restarting host's apache web server..." call "service apache2 restart"
echo "Done."
exit 0
