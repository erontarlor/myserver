#!/bin/bash
#
# setup.sh V0.1
#
# Script for setting up a private web server with pre-configured OwnCloud
# service and automatically renewing Let's Encrypt SSL certificates, based
# on a basic Ubuntu 18.04 cloud server with root access, using docker images.
#
# (c) 2018 by erontarlor
#

declare -i step=1
declare -i debug=0
declare -i auto=0
declare -i testCertificates=0

declare rootPassword
declare -i userCount=1
declare -a userName
declare -a userFullName
declare -a userEMail
declare -a userPassword
declare -a userSudo
userName[0]=admin
userSudo[0]=1

declare ownCloudPassword=changeme

declare -i certificateCount=1
declare -a certificateDomain
declare -a certificateCountry
declare -a certificateState
declare -a certificateCity
declare -a certificateOrganization
declare -a certificateEMail
certificateDomain[0]=localhost

declare -i sshdPort=22

declare configFile=setup.cfg
if [ -e "$configFile" ]
then
  source $configFile
fi

declare sshdConfig=/etc/ssh/sshd_config


getArgs()
{
  for arg in "$@"
  do
    if [ "$arg" = "-auto" ]
    then
      auto=1
    elif [ "$arg" = "-debug" ]
    then
      debug=1
    elif [ "$arg" = "-testcertificates" ]
    then
      testCertificates=1
    fi
  done
}


call()
{
  if [ "$debug" = 1 ]
  then
    echo "$1"
  else
    eval $1
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


askYesOrNo()
{
  declare default
  declare answer
  if [ "$2" = 1 ]
  then
    default="Y/n"
    answer="y"
  else
    default="y/N"
    answer="n"
  fi
  while [ "$auto" = 1 ] || read -r -p "$1 [$default]? " answer
  do
    if [ -z "$answer" ]
    then
      if [ "$2" = 1 ]
      then
        answer=0
      else
        answer=1
      fi
      break 
    elif [[ "$answer" = [Nn] ]]
    then
      answer=1
      break
    elif [[ "$answer" = [Yy] ]]
    then
      answer=0
      break
    fi
  done
  return $answer
}


declare integer
askInteger()
{
  integer=$2
  while [ "$auto" = 1 ] || read -r -p "$1 [$2]? " integer
  do
    integer="${integer:-$2}"
    if [[ "$integer" =~ ^[0-9][0-9]*$ ]] && [ "$integer" -gt 0 ] && [ "$integer" -lt 65535 ]
    then
      break
    fi
  done
  return $integer
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


declare password
askPassword()
{
  declare default
  if [ ! -z "$2" ]
  then
    default="********"
  fi
  password=$2
  while [ "$auto" = 1 ] || read -s -r -p "$1 [$default]: " password
  do
    password="${password:-$2}"
    if [ ! -z "$password" ]
    then
      break
    fi
  done
}


changeRootPassword()
{
  askPassword "Enter root password" "$rootPassword"
  rootPassword=$password
  call "echo \"root:$rootPassword\" | chpasswd"
}


userExists()
{
  id -u $1 >/dev/null 2>&1
  return $?
}


addUser()
{
  askValue "Enter user name" "${userName[$1]}"
  userName[$1]=$value
  askValue "Enter user's full name" "${userFullName[$1]}"
  userFullName[$1]=$value
  askValue "Enter user's e-mail" "${userEMail[$1]}"
  userEMail[$1]=$value
  askPassword "Enter password" "${userPassword[$1]}"
  userPassword[$1]=$password
  if userExists ${userName[$1]}
  then
    echo "User ${userName[$1]} already exists"
  else
    echo "Adding user ${userName[$1]}"
    call "useradd -m -d /home/${userName[$1]} -c \"${userFullName[$1]},,,\" -s /bin/bash ${userName[$1]}"
  fi
  echo "Changing password..."
  call "echo \"${userName[$1]}:${userPassword[$1]}\" | chpasswd"
  if [ "$1" = 0 ] || askYesOrNo "Do you want the user to be a sudo user" ${userSudo[$1]}
  then
    echo "Making user a sudo user..."
    userSudo[$1]=1
    call "usermod -aG sudo ${userName[$1]}"
  else
    userSudo[$1]=0
  fi
}


addAdditionalUser()
{
  if [ "$auto" = 1 ]
  then
    declare count=$userCount
    while [ "$count" -gt 1 ]
    do
      let count=count-1
      addUser $count
    done
  else
    while askYesOrNo "Do you want to add another user"
    do
      addUser $userCount
      let userCount=userCount+1
    done
  fi
}


installTools()
{
  call "apt-get update"
  call "apt-get install vim-gtk apt-transport-https ca-certificates curl software-properties-common -y"
}


addLetsEncryptRepository()
{
  call "add-apt-repository ppa:certbot/certbot -n -y"
}


addDockerRepository()
{
  call "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -"
  call "add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable\" -n -y"
}


installLetsEncrypt()
{
  call "apt install python-certbot-apache -y"
  declare file="/etc/cron.weekly/letsencrypt"
  call "echo \"#!/bin/sh\" > $file"
  call "echo \"certbot renew\" >> $file"
  call "chmod a+x $file"
}


installDocker()
{
  call "apt-get install docker-ce -y"
  call "curl -L \"https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
  call "chmod +x /usr/local/bin/docker-compose"
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
}


createSslCertificate()
{
  echo "Creating SSL certificate for domain ${certificateDomain[$1]}..."
  if [ "$testCertificates" = 1 ]
  then
    call "openssl genrsa -out ${certificateDomain[$1]}.key 1024"
    call "openssl req -new -subj \"/C=${certificateCountry[$1]}/ST=${certificateState[$1]}/L=${certificateCity[$1]}/O=${certificateOrganization[$1]}/OU=none/CN=${certificateDomain[$1]}/Email=${certificateEMail[$1]}\" -key ${certificateDomain[$1]}.key -out ${certificateDomain[$1]}.pem"
    call "cp ${certificateDomain[$1]}.key ${certificateDomain[$1]}.key.org"
    call "cp ${certificateDomain[$1]}.pem ${certificateDomain[$1]}.pem.org"
    call "openssl rsa -in ${certificateDomain[$1]}.key.org -out ${certificateDomain[$1]}.key"
    call "openssl x509 -req -days 365 -in ${certificateDomain[$1]}.pem.org -signkey ${certificateDomain[$1]}.key -out ${certificateDomain[$1]}.pem"
    call "rm ${certificateDomain[$1]}.key.org ${certificateDomain[$1]}.pem.org"
    call "mv ${certificateDomain[$1]}.pem /etc/ssl/certs"
    call "mv ${certificateDomain[$1]}.key /etc/ssl/private"
    call "chown root:root /etc/ssl/certs/${certificateDomain[$1]}.pem"
    call "chmod 644 /etc/ssl/certs/${certificateDomain[$1]}.pem"
    call "chown root:ssl-cert /etc/ssl/private/${certificateDomain[$1]}.key"
    call "chmod 640 /etc/ssl/private/${certificateDomain[$1]}.key"
  else
    #call "certbot --apache --test-cert --agree-tos -n -d ${certificateDomain[$1]} -m ${certificateEMail[$1]}"
    call "certbot --apache --agree-tos -n -d ${certificateDomain[$1]} -m ${certificateEMail[$1]}"
  fi
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
  declare serverName=${certificateDomain[$1]}
  declare file="/etc/apache2/sites-available/000-$serverName.conf"
  call "echo \"<IfModule mod_ssl.c>\" > $file"
  if [ "$testcertificates" = 1 ]
  then
    call "echo \"<VirtualHost *:443>\" >> $file"
  else
    call "echo \"<VirtualHost *:80>\" >> $file"
    call "echo \"DocumentRoot /var/www/html\" >> $file"
  fi
  call "echo \"ServerName $serverName\" >> $file"
  #call "echo \"ServerAlias www.$serverName\" >> $file"
  call "echo \"ServerAdmin ${certificateEMail[$1]}\" >> $file"
  call "echo \"ProxyPass / http://localhost:8080/\" >> $file"
  call "echo \"ProxyPassReverse / http://localhost:8080/\" >> $file"
  call "echo 'ErrorLog \${APACHE_LOG_DIR}/error.log' >> $file"
  call "echo 'CustomLog \${APACHE_LOG_DIR}/ssl_access.log combined' >> $file"
  # Possible values include: debug, info, notice, warn, error, crit,
  # alert, emerg.
  call "echo \"LogLevel warn\" >> $file"
  call "echo \"Header always set Strict-Transport-Security \\\"max-age=15552000; includeSubdomains;\\\"\" >> $file"
  if [ "$testcertificates" = 1 ]
  then
    #   SSL Engine Switch:
    #   Enable/Disable SSL for this virtual host.
    #SSLEngine on
    #   A self-signed (snakeoil) certificate can be created by installing
    #   the ssl-cert package. See
    #   /usr/share/doc/apache2.2-common/README.Debian.gz for more info.
    #   If both key and certificate are stored in the same file, only the
    #   SSLCertificateFile directive is needed.
    call "echo \"SSLCertificateFile    /etc/ssl/certs/$serverName.pem\" >> $file"
    call "echo \"SSLCertificateKeyFile /etc/ssl/private/$serverName.key\" >> $file"
    #   Server Certificate Chain:
    #   Point SSLCertificateChainFile at a file containing the
    #   concatenation of PEM encoded CA certificates which form the
    #   certificate chain for the server certificate. Alternatively
    #   the referenced file can be the same as SSLCertificateFile
    #   when the CA certificates are directly appended to the server
    #   certificate for convinience.
    call "echo \"SSLCertificateChainFile /etc/ssl/certs/$serverName.pem\" >> $file"
    #   Certificate Authority (CA):
    #   Set the CA certificate verification path where to find CA
    #   certificates for client authentication or alternatively one
    #   huge file containing all of them (file must be PEM encoded)
    #   Note: Inside SSLCACertificatePath you need hash symlinks
    #         to point to the certificate files. Use the provided
    #         Makefile to update the hash symlinks after changes.
    #SSLCACertificatePath /etc/ssl/certs/
    #SSLCACertificateFile /etc/apache2/ssl.crt/ca-bundle.crt
    #   Certificate Revocation Lists (CRL):
    #   Set the CA revocation path where to find CA CRLs for client
    #   authentication or alternatively one huge file containing all
    #   of them (file must be PEM encoded)
    #   Note: Inside SSLCARevocationPath you need hash symlinks
    #         to point to the certificate files. Use the provided
    #         Makefile to update the hash symlinks after changes.
    #SSLCARevocationPath /etc/apache2/ssl.crl/
    #SSLCARevocationFile /etc/apache2/ssl.crl/ca-bundle.crl
    #   Client Authentication (Type):
    #   Client certificate verification type and depth.  Types are
    #   none, optional, require and optional_no_ca.  Depth is a
    #   number which specifies how deeply to verify the certificate
    #   issuer chain before deciding the certificate is not valid.
    #SSLVerifyClient require
    #SSLVerifyDepth  10
    #   Access Control:
    #   With SSLRequire you can do per-directory access control based
    #   on arbitrary complex boolean expressions containing server
    #   variable checks and other lookup directives.  The syntax is a
    #   mixture between C and Perl.  See the mod_ssl documentation
    #   for more details.
    #<Location />
    #SSLRequire (    %{SSL_CIPHER} !~ m/^(EXP|NULL)/ \
    #            and %{SSL_CLIENT_S_DN_O} eq "Snake Oil, Ltd." \
    #            and %{SSL_CLIENT_S_DN_OU} in {"Staff", "CA", "Dev"} \
    #            and %{TIME_WDAY} >= 1 and %{TIME_WDAY} <= 5 \
    #            and %{TIME_HOUR} >= 8 and %{TIME_HOUR} <= 20       ) \
    #           or %{REMOTE_ADDR} =~ m/^192\.76\.162\.[0-9]+$/
    #</Location>
    #   SSL Engine Options:
    #   Set various options for the SSL engine.
    #   o FakeBasicAuth:
    #     Translate the client X.509 into a Basic Authorisation.  This means that
    #     the standard Auth/DBMAuth methods can be used for access control.  The
    #     user name is the `one line' version of the client's X.509 certificate.
    #     Note that no password is obtained from the user. Every entry in the user
    #     file needs this password: `xxj31ZMTZzkVA'.
    #   o ExportCertData:
    #     This exports two additional environment variables: SSL_CLIENT_CERT and
    #     SSL_SERVER_CERT. These contain the PEM-encoded certificates of the
    #     server (always existing) and the client (only existing when client
    #     authentication is used). This can be used to import the certificates
    #     into CGI scripts.
    #   o StdEnvVars:
    #     This exports the standard SSL/TLS related `SSL_*' environment variables.
    #     Per default this exportation is switched off for performance reasons,
    #     because the extraction step is an expensive operation and is usually
    #     useless for serving static content. So one usually enables the
    #     exportation for CGI and SSI requests only.
    #   o StrictRequire:
    #     This denies access when "SSLRequireSSL" or "SSLRequire" applied even
    #     under a "Satisfy any" situation, i.e. when it applies access is denied
    #     and no other module can change it.
    #   o OptRenegotiate:
    #     This enables optimized SSL connection renegotiation handling when SSL
    #     directives are used in per-directory context.
    #SSLOptions +FakeBasicAuth +ExportCertData +StrictRequire
    call "echo \"<FilesMatch \\\"\\\\.(cgi|shtml|phtml|php)$\\\">\" >> $file"
    call "echo \"SSLOptions +StdEnvVars\" >> $file"
    call "echo \"</FilesMatch>\" >> $file"
    call "echo \"<Directory /usr/lib/cgi-bin>\" >> $file"
    call "echo \"SSLOptions +StdEnvVars\" >> $file"
    call "echo \"</Directory>\" >> $file"
    #   SSL Protocol Adjustments:
    #   The safe and default but still SSL/TLS standard compliant shutdown
    #   approach is that mod_ssl sends the close notify alert but doesn't wait for
    #   the close notify alert from client. When you need a different shutdown
    #   approach you can use one of the following variables:
    #   o ssl-unclean-shutdown:
    #     This forces an unclean shutdown when the connection is closed, i.e. no
    #     SSL close notify alert is send or allowed to received.  This violates
    #     the SSL/TLS standard but is needed for some brain-dead browsers. Use
    #     this when you receive I/O errors because of the standard approach where
    #     mod_ssl sends the close notify alert.
    #   o ssl-accurate-shutdown:
    #     This forces an accurate shutdown when the connection is closed, i.e. a
    #     SSL close notify alert is send and mod_ssl waits for the close notify
    #     alert of the client. This is 100% SSL/TLS standard compliant, but in
    #     practice often causes hanging connections with brain-dead browsers. Use
    #     this only for browsers where you know that their SSL implementation
    #     works correctly.
    #   Notice: Most problems of broken clients are also related to the HTTP
    #   keep-alive facility, so you usually additionally want to disable
    #   keep-alive for those clients, too. Use variable "nokeepalive" for this.
    #   Similarly, one has to force some clients to use HTTP/1.0 to workaround
    #   their broken HTTP/1.1 implementation. Use variables "downgrade-1.0" and
    #   "force-response-1.0" for this.
    call "echo \"BrowserMatch \\\"MSIE [2-6]\\\" \\\\\" >> $file"
    call "echo \"nokeepalive ssl-unclean-shutdown \\\\\" >> $file"
    call "echo \"downgrade-1.0 force-response-1.0\" >> $file"
    # MSIE 7 and newer should be able to use keepalive\" >> $file"
    call "echo \"BrowserMatch \\\"MSIE [17-9]\\\" ssl-unclean-shutdown\" >> $file"
    call "echo \"<IfModule mod_headers.c>\" >> $file"
    call "echo \"Header always set Strict-Transport-Security \\\"max-age=15552000; includeSubDomains; preload\\\"\" >> $file"
    call "echo \"</IfModule>\" >> $file"
  fi
  call "echo \"</VirtualHost>\" >> $file"
  call "echo \"</IfModule>\" >> $file"
  createLink "$file" "/etc/apache2/sites-enabled/000-$serverName.conf"
  createSslCertificate $1
}


declare passwordSha1
calculatePasswordSha1()
{
  declare array
  call "array=(\$( echo -n \"$1\" | sha1sum ))"
  passwordSha1=${array[0]}
}


installOwnCloud()
{
  createWebSite 0
  askPassword "Enter OwnCloud admin password" $ownCloudPassword
  ownCloudPassword=$password
  if [ ! -d owncloud ]
  then
    call "mkdir owncloud"
  fi
  call "cd owncloud"
  declare file=".env"
  call "echo \"OWNCLOUD_VERSION=10.0\" > $file"
  call "chmod 600 $file"
  call "echo \"OWNCLOUD_DOMAIN=localhost\" >> $file"
  call "echo \"ADMIN_USERNAME=admin\" >> $file"
  call "echo \"ADMIN_PASSWORD=$ownCloudPassword\" >> $file"
  call "echo \"HTTP_PORT=8080\" >> $file"
  call "wget -O docker-compose.yml https://raw.githubusercontent.com/owncloud-docker/server/master/docker-compose.yml"
  call "sed -e \"s/version: '2.1'/version: '2.2'/\" -i docker-compose.yml"
  call "sed -e 's/\(- OWNCLOUD_DOMAIN=.*\)$/\1\n\ \ \ \ \ \ - OWNCLOUD_OVERWRITE_HOST=${certificateDomain[0]}\n\ \ \ \ \ \ - OWNCLOUD_OVERWRITE_PROTOCOL=https\n\ \ \ \ \ \ - OWNCLOUD_OVERWRITE_WEBROOT=\/\n\ \ \ \ \ \ - OWNCLOUD_OVERWRITE_CLI_URL=https:\/\/${certificateDomain[0]}\n\ \ \ \ \ \ - OWNCLOUD_HTACCESS_REWRITE_BASE=\//' -i docker-compose.yml"
  call "docker-compose up -d"
  sleep 30
  echo "Changing admin password..."
  calculatePasswordSha1 "$ownCloudPassword"
  call "docker-compose exec owncloud mysql -h db -powncloud -P 3306 -u owncloud -D owncloud -e \"update oc_users set password='$passwordSha1' where uid='admin';\""
  echo "Installing additional apps..."
  call "docker-compose exec owncloud occ market:install announcementcenter"
  call "docker-compose exec owncloud occ market:install audioplayer"
  call "docker-compose exec owncloud occ market:install brute_force_protection"
  call "docker-compose exec owncloud occ market:install calendar"
  call "docker-compose exec owncloud occ market:install cms_pico"
  call "docker-compose exec owncloud occ market:install contacts"
  call "docker-compose exec owncloud occ market:install drawio"
  call "docker-compose exec owncloud occ market:install files_pdfviewer"
  call "docker-compose exec owncloud occ market:install files_reader"
  call "docker-compose exec owncloud occ market:install files_texteditor"
  call "docker-compose exec owncloud occ market:install files_textviewer"
  call "docker-compose exec owncloud occ market:install gallery"
  call "docker-compose exec owncloud occ market:install notes"
  call "docker-compose exec owncloud occ market:install password_policy"
  call "docker-compose exec owncloud occ market:install polls"
  call "docker-compose exec owncloud occ market:install tasks"
  call "docker-compose exec owncloud occ market:install wallpaper"
  echo "Adding users..."
  declare count=$userCount
  while [ "$count" -gt 0 ]
  do
    let count=count-1
    call "docker-compose exec -e OC_PASS=\"${userPassword[$count]}\" owncloud occ user:add --password-from-env --display-name=\"${userFullName[$count]}\" --group=\"users\" --email=${userEMail[$count]} ${userName[$count]}"
  done
  echo "Restarting OwnCloud..."
  call "docker-compose restart owncloud"
  call "cd .."
}


disableSshRootLogin()
{
  call "sed -e 's/^\( *PermitRootLogin .*\)$/#\1/' -i $sshdConfig"
  call "echo \"PermitRootLogin no\" >> $sshdConfig"
}


changeSshPort()
{
  askInteger "Which port do you want to use for SSH" $sshdPort
  sshdPort=$integer
  echo "Changing SSL port to $sshdPort..."
  call "sed -e 's/^\( *Port .*$\)/#\1/' -i $sshdConfig"
  call "echo \"Port $sshdPort\" >> $sshdConfig"
}


saveSettings()
{
  declare file=setup.cfg
  declare newFile=$file.new
  call "echo \"rootPassword='$rootPassword'\" > $newFile"
  call "chmod 600 $newFile"
  call "echo \"userCount=$userCount\" >> $newFile"
  declare count=$userCount
  while [ "$count" -gt 0 ]
  do
    let count=count-1
    call "echo \"userName[$count]='${userName[$count]}'\" >> $newFile"
    call "echo \"userFullName[$count]='${userFullName[$count]}'\" >> $newFile"
    call "echo \"userEMail[$count]='${userEMail[$count]}'\" >> $newFile"
    call "echo \"userSudo[$count]='${userSudo[$count]}'\" >> $newFile"
    call "echo \"userPassword[$count]='${userPassword[$count]}'\" >> $newFile"
  done
  call "echo \"ownCloudPassword='$ownCloudPassword'\" >> $newFile"
  call "echo \"certificateCount=$certificateCount\" >> $newFile"
  declare count=$certificateCount
  while [ "$count" -gt 0 ]
  do
    let count=count-1
    call "echo \"certificateDomain[$count]='${certificateDomain[$count]}'\" >> $newFile"
    call "echo \"certificateCountry[$count]='${certificateCountry[$count]}'\" >> $newFile"
    call "echo \"certificateState[$count]='${certificateState[$count]}'\" >> $newFile"
    call "echo \"certificateCity[$count]='${certificateCity[$count]}'\" >> $newFile"
    call "echo \"certificateOrganization[$count]='${certificateOrganization[$count]}'\" >> $newFile"
    call "echo \"certificateEMail[$count]='${certificateEMail[$count]}'\" >> $newFile"
  done
  call "echo \"sshdPort=$sshdPort\" >> $newFile"
  if [ -e "$file" ]
  then
    call "mv $file $file.old"
  fi
  call "mv $newFile $file"
}


getArgs "$@"
if [ "$debug" = 1 ]
then
  echo "Using debug mode: no changes are done to the system."
fi
if [ "$auto" = 1 ]
then
  echo "Using auto mode: no user interaction, just using same values as last time."
else
  echo "Using interactive mode: querying data from user."
  userCount=1
  certificateCount=1
fi
if [ "$testCertificates" = 1 ]
then
  echo "Using self signed test SSL certificates."
else
  echo "Using SSL certificates from Let's Encrypt."
fi
runStep "Changing root password..." changeRootPassword
runStep "Adding main user..." addUser 0
runStep "Adding additional users..." addAdditionalUser
runStep "Installing tools..." installTools
runStep "Adding Let's Encrypt repository..." addLetsEncryptRepository
runStep "Adding Docker repository..." addDockerRepository
runStep "Updating package database..." call "apt-get update"
runStep "Installing Let's Encrypt..." installLetsEncrypt
runStep "Installing Docker..." installDocker
runStep "Configuring host's apache web server..." configureApache
runStep "Installing Docker container OwnCloud..." installOwnCloud
runStep "Restarting host's apache web server..." call "service apache2 restart"
runStep "Disabling SSH root login..." disableSshRootLogin
runStep "Changing SSH port..." changeSshPort
runStep "Restarting SSH daemon..." call "systemctl restart ssh.service"
saveSettings
echo "Done."
exit 0

