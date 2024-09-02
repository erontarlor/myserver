#!/bin/bash
#
# setup.sh V0.4
#
# Script for setting up the automatically renewing Let's Encrypt SSL certificates.
#
# (c) 2024 by erontarlor
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


createSslCertificate()
{
  echo "Creating SSL certificate for domain ${certificateDomain[$1]}..."
  #call "certbot --apache --test-cert --agree-tos -n -d ${certificateDomain[$1]} -m ${certificateEMail[$1]}"
  call "certbot --apache --agree-tos -n -d ${certificateDomain[$1]} -m ${certificateEMail[$1]}"
}


createLink()
{
  if [ ! -e "$2" ]
  then
    call "ln -s \"$1\" \"$2\""
  fi
}


createWebSite()
{
  askValue "Enter domain name" "${certificateDomain[$1]}"
  certificateDomain[$1]=$value
  askValue "Enter country abbreviation" "${certificateCountry[$1]}"
  certificateCountry[$1]=$value
  askValue "Enter state" "${certificateState[$1]}"
  certificateState[$1]=$value
  askValue "Enter city" "${certificateCity[$1]}"
  certificateCity[$1]=$value
  askValue "Enter organization" "${certificateOrganization[$1]}"
  certificateOrganization[$1]=$value
  askValue "Enter e-mail" "${certificateEMail[$1]}"
  certificateEMail[$1]=$value
  declare id=$(printf '%3.3d' $1)
  declare serverName=${certificateDomain[$1]}
  declare file="/etc/apache2/sites-available/$id-$serverName.conf"
  call "echo \"<IfModule mod_ssl.c>\" > $file"
  call "echo \"<VirtualHost *:80>\" >> $file"
  call "echo \"DocumentRoot /var/www/html\" >> $file"
  call "echo \"ServerName $serverName\" >> $file"
  #call "echo \"ServerAlias www.$serverName\" >> $file"
  call "echo \"ServerAdmin ${certificateEMail[$1]}\" >> $file"
  
  if [ "$serverName" == "nextcloud.gaudiversum.de" ]
  then
    call "echo \"ProxyPass /sites/ http://localhost:8080//index.php/apps/cms_pico/pico/\" >> $file"
    call "echo \"ProxyPassReverse /sites/ http://localhost:8080//index.php/apps/cms_pico/pico/\" >> $file"
    call "echo \"ProxyPass / http://localhost:8080/\" >> $file"
    call "echo \"ProxyPassReverse / http://localhost:8080/\" >> $file"
  elif [ "$serverName" == "www.gaudiumludendi.de" ]
  then
    call "echo \"ProxyPass /robots.txt http://localhost:8080/index.php/apps/cms_pico/pico/gaudiumludendi/assets/robots.txt\" >> $file"
    call "echo \"ProxyPassReverse /robots.txt http://localhost:8080/index.php/apps/cms_pico/pico/gaudiumludendi/assets/robots.txt\" >> $file"
    call "echo \"ProxyPass /index.php/ http://localhost:8080/index.php/\" >> $file"
    call "echo \"ProxyPassReverse /index.php/ http://localhost:8080/index.php/\" >> $file"
    call "echo \"ProxyPass /custom/ http://localhost:8080/custom/\" >> $file"
    call "echo \"ProxyPassReverse /custom/ http://localhost:8080/custom/\" >> $file"
    call "echo \"ProxyPass /custom_apps/ http://localhost:8080/custom_apps/\" >> $file"
    call "echo \"ProxyPassReverse /custom_apps/ http://localhost:8080/custom_apps/\" >> $file"
    call "echo \"ProxyPass /sites/ http://localhost:8080/index.php/apps/cms_pico/pico/\" >> $file"
    call "echo \"ProxyPassReverse /sites/ http://localhost:8080/index.php/apps/cms_pico/pico/\" >> $file"
    call "echo \"ProxyPass / http://localhost:8080//index.php/apps/cms_pico/pico/gaudiumludendi/\" >> $file"
    call "echo \"ProxyPassReverse / http://localhost:8080//index.php/apps/cms_pico/pico/gaudiumludendi\" >> $file"
  elif [ "$serverName" == "seifenoper.gaudiversum.de" ]
  then
    call "echo \"ProxyPass /robots.txt http://localhost:8080/index.php/apps/cms_pico/pico/soapopera/assets/robots.txt\" >> $file"
    call "echo \"ProxyPassReverse /robots.txt http://localhost:8080/index.php/apps/cms_pico/pico/soapopera/assets/robots.txt\" >> $file"
    call "echo \"ProxyPass /index.php/ http://localhost:8080/index.php/\" >> $file"
    call "echo \"ProxyPassReverse /index.php/ http://localhost:8080/index.php/\" >> $file"
    call "echo \"ProxyPass /custom/ http://localhost:8080/custom/\" >> $file"
    call "echo \"ProxyPassReverse /custom/ http://localhost:8080/custom/\" >> $file"
    call "echo \"ProxyPass /custom_apps/ http://localhost:8080/custom_apps/\" >> $file"
    call "echo \"ProxyPassReverse /custom_apps/ http://localhost:8080/custom_apps/\" >> $file"
    call "echo \"ProxyPass /sites/ http://localhost:8080/index.php/apps/cms_pico/pico/\" >> $file"
    call "echo \"ProxyPassReverse /sites/ http://localhost:8080/index.php/apps/cms_pico/pico/\" >> $file"
    call "echo \"ProxyPass / http://localhost:8080//index.php/apps/cms_pico/pico/soapopera/\" >> $file"
    call "echo \"ProxyPassReverse / http://localhost:8080//index.php/apps/cms_pico/pico/soapopera\" >> $file"
  elif [ "$serverName" == "gallery.gaudiversum.de" ]
  then
    call "echo \"ProxyPass /froschteich http://localhost:8080/apps/gallery/s/nzWzBHHMdwQCfa9\" >> $file"
    call "echo \"ProxyPassReverse /froschteich http://localhost:8080/apps/gallery/s/nzWzBHHMdwQCfa9\" >> $file"
    call "echo \"ProxyPass /tkd http://localhost:8080/apps/gallery/s/67EiDLHLhUHuJ2R\" >> $file"
    call "echo \"ProxyPassReverse /tkd http://localhost:8080/apps/gallery/s/67EiDLHLhUHuJ2R\" >> $file"
    call "echo \"ProxyPass /aufbaukurs http://localhost:8080/apps/gallery/s/QBo0TpxiRp0QLuf\" >> $file"
    call "echo \"ProxyPassReverse /aufbaukurs http://localhost:8080/apps/gallery/s/QBo0TpxiRp0QLuf\" >> $file"
    call "echo \"ProxyPass /tanzen http://localhost:8080/s/d6W83ahgNJ1lJj8\" >> $file"
    call "echo \"ProxyPassReverse /tanzen http://localhost:8080/s/d6W83ahgNJ1lJj8\" >> $file"
    call "echo \"ProxyPass /stopmotion http://localhost:8080/s/9EpfG54Is6lq22J\" >> $file"
    call "echo \"ProxyPassReverse /stopmotion http://localhost:8080/s/9EpfG54Is6lq22J\" >> $file"
    call "echo \"ProxyPass /warriorsparty http://localhost:8080/s/1cSky3hYafYGXUG\" >> $file"
    call "echo \"ProxyPassReverse /warriorsparty http://localhost:8080/s/1cSky3hYafYGXUG\" >> $file"
    call "echo \"ProxyPass / http://localhost:8080/\" >> $file"
    call "echo \"ProxyPassReverse / http://localhost:8080/\" >> $file"
  else
    call "echo \"ProxyPass / http://localhost:8080/\" >> $file"
    call "echo \"ProxyPassReverse / http://localhost:8080/\" >> $file"
  fi
  
  call "echo 'ErrorLog \${APACHE_LOG_DIR}/error.log' >> $file"
  call "echo 'CustomLog \${APACHE_LOG_DIR}/ssl_access.log combined' >> $file"
  # Possible values include: debug, info, notice, warn, error, crit,
  # alert, emerg.
  call "echo \"LogLevel warn\" >> $file"
  call "echo \"<IfModule mod_headers.c>\" >> $file"
  call "echo \"Header unset X-Robots-Tag\" >> $file"
  call "echo \"Header unset Pragma\" >> $file"
  call "echo \"Header set Cache-Control \\\"public, must-revalidate\\\"\" >> $file"
  call "echo \"Header always set Strict-Transport-Security \\\"max-age=15552000; includeSubDomains; preload\\\"\" >> $file"
  call "echo \"</IfModule>\" >> $file"
  call "echo \"</VirtualHost>\" >> $file"
  call "echo \"</IfModule>\" >> $file"
  createLink "$file" "/etc/apache2/sites-enabled/$id-$serverName.conf"
  createSslCertificate $1
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
