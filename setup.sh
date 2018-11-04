#!/bin/bash

declare -i step=1
declare -i debug=0
declare -i auto=0

declare rootPassword
declare -i userCount=1
declare -a userName
declare -a userFullName
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
certificateDomain[0]=localhost

declare -i sshdPort=22

declare configFile=setup.cfg
if [ -f "$configFile" ]
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


addUser()
{
  askValue "Enter user name" "${userName[$1]}"
  userName[$1]=$value
  askValue "Enter user's full name" "${userFullName[$1]}"
  userFullName[$1]=$value
  askPassword "Enter password" "${userPassword[$1]}"
  userPassword[$1]=$password
  call "useradd -m -d /home/${userName[$1]} -c \"${userFullName[$1]},,,\" -s /bin/bash ${userName[$1]}"
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


createSslCertificate()
{
  askValue "Enter domain name" ${certificateDomain[$1]}
  certificateDomain[$1]=$value
  askValue "Enter country abbreviation" ${certificateCountry[$1]}
  certificateCountry[$1]=$value
  askValue "Enter state" ${certificateState[$1]}
  certificateState[$1]=$value
  askValue "Enter city" ${certificateCity[$1]}
  certificateCity[$1]=$value
  askValue "Enter organization" ${certificateOrganization[$1]}
  certificateOrganization[$1]=$value
  call "openssl genrsa -out ${certificateDomain[$1]}.key 1024"
  call "openssl req -new -subj \"/C=${certificateCountry[$1]}/ST=${certificateState[$1]}/L=${certificateCity[$1]}/O=${certificateOrganization[$1]}/OU=none/CN=${certificateDomain[$1]}\" -key ${certificateDomain[$1]}.key -out ${certificateDomain[$1]}.pem"
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
}


createAdditionalSslCertificate()
{
  if [ "$auto" = 1 ]
  then
    declare count=$certificateCount
    while [ "$count" -gt 1 ]
    do
      let count=count-1
      createSslCertificate $count
    done
  else
    while askYesOrNo "Do you want to create another SSL certificate"
    do
      createSslCertificate $certificateCount
      let certificateCount=certificateCount+1
    done
  fi
}


installDocker()
{
  call "apt-get install apt-transport-https ca-certificates curl software-properties-common -y"
  call "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -"
  call "add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable\""
  call "apt-get update"
  call "apt-get install docker-ce -y"
  call "curl -L \"https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
  call "chmod +x /usr/local/bin/docker-compose"
}


createSslConf()
{
  declare file=ssl.conf

  call "echo '<VirtualHost *:\${APACHE_LISTEN}>' > $file"
  call "echo 'ServerAdmin \${APACHE_SERVER_ADMIN}' >> $file"
  call "echo 'DocumentRoot \${APACHE_DOCUMENT_ROOT}' >> $file"

  call "echo 'ErrorLog \${APACHE_ERROR_LOG}' >> $file"
  call "echo 'CustomLog \${APACHE_ACCESS_LOG} \${APACHE_LOG_FORMAT}' >> $file"

  #   SSL Engine Switch:
  #   Enable/Disable SSL for this virtual host.
  call "echo 'SSLEngine on' >> $file"

  #   A self-signed (snakeoil) certificate can be created by installing
  #   the ssl-cert package. See
  #   /usr/share/doc/apache2.2-common/README.Debian.gz for more info.
  #   If both key and certificate are stored in the same file, only the
  #   SSLCertificateFile directive is needed.
  call "echo \"SSLCertificateFile    /etc/ssl/certs/${certificateDomain[0]}.pem\" >> $file"
  call "echo \"SSLCertificateKeyFile /etc/ssl/private/${certificateDomain[0]}.key\" >> $file"

  #   Server Certificate Chain:
  #   Point SSLCertificateChainFile at a file containing the
  #   concatenation of PEM encoded CA certificates which form the
  #   certificate chain for the server certificate. Alternatively
  #   the referenced file can be the same as SSLCertificateFile
  #   when the CA certificates are directly appended to the server
  #   certificate for convinience.
  call "echo \"SSLCertificateChainFile /etc/ssl/certs/${certificateDomain[0]}.pem\" >> $file"

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
  call "echo \"<FilesMatch \\\"\.(cgi|shtml|phtml|php)$\\\">\" >> $file"
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
  # MSIE 7 and newer should be able to use keepalive
  call "echo \"BrowserMatch \\\"MSIE [17-9]\\\" ssl-unclean-shutdown\" >> $file"

  call "echo '<Directory \${APACHE_DOCUMENT_ROOT}>' >> $file"
  call "echo \"AllowOverride All\" >> $file"
  call "echo \"Options -Indexes +FollowSymlinks\" >> $file"
  call "echo \"</Directory>\" >> $file"
  call "echo \"</VirtualHost>\" >> $file"
}


installOwnCloud()
{
  askPassword "Enter OwnCloud admin password" $ownCloudPassword
  ownCloudPassword=$password
  declare file=".env"
  call "echo \"OWNCLOUD_VERSION=10.0\" > $file"
  call "echo \"OWNCLOUD_DOMAIN=localhost\" >> $file"
  call "echo \"ADMIN_USERNAME=admin\" >> $file"
  call "echo \"ADMIN_PASSWORD=$ownCloudPassword\" >> $file"
  call "echo \"HTTP_PORT=443\" >> $file"
  call "wget -O docker-compose.yml https://raw.githubusercontent.com/owncloud-docker/server/master/docker-compose.yml"
  call "docker-compose up -d"
  call "docker cp /etc/ssl/certs/${certificateDomain[0]}.pem "'$(docker ps -q -f name=owncloud)'":/etc/ssl/certs"
  call "docker cp /etc/ssl/private/${certificateDomain[0]}.key "'$(docker ps -q -f name=owncloud)'":/etc/ssl/private"
  call "docker-compose exec owncloud chown root:root /etc/ssl/certs/${certificateDomain[0]}.pem"
  call "docker-compose exec owncloud chmod 644 /etc/ssl/certs/${certificateDomain[0]}.pem"
  call "docker-compose exec owncloud chown root:ssl-cert /etc/ssl/private/${certificateDomain[0]}.key"
  call "docker-compose exec owncloud chmod 640 /etc/ssl/private/${certificateDomain[0]}.key"
  call "docker-compose exec owncloud ln -s /etc/apache2/mods-available/socache_shmcb.load /etc/apache2/mods-enabled"
  call "docker-compose exec owncloud ln -s /etc/apache2/mods-available/ssl.conf /etc/apache2/mods-enabled"
  call "docker-compose exec owncloud ln -s /etc/apache2/mods-available/ssl.load /etc/apache2/mods-enabled"
  createSslConf
  call 'docker cp ssl.conf $(docker ps -q -f name=owncloud):/etc/apache2/conf-enabled'
  call "docker-compose exec owncloud chown root:root /etc/apache2/conf-enabled/ssl.conf"
  call "docker-compose exec owncloud chmod 644 /etc/apache2/conf-enabled/ssl.conf"
  call "docker-compose restart owncloud"
  call "rm ssl.conf"
}


disableSshRootLogin()
{
  call "sed -e 's/^\( *PermitRootLogin .*\)$/#\1/' $sshdConfig > $sshdConfig.new && mv $sshdConfig.new $sshdConfig"
  call "echo \"PermitRootLogin no\" >> $sshdConfig"
}


changeSshPort()
{
  askInteger "Which port do you want to use for SSH" $sshdPort
  sshdPort=$integer
  call "sed -e 's/^\( *Port .*$\)/#\1/' $sshdConfig > $sshdConfig.new && mv $sshdConfig.new $sshdConfig"
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
  done
  call "echo \"sshdPort=$sshdPort\" >> $newFile"
  if [ -f "$file" ]
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

runStep "Changing root password..." changeRootPassword
runStep "Adding main user..." addUser 0
runStep "Adding additional users..." addAdditionalUser
runStep "Creating SSL certificate..." createSslCertificate 0
runStep "Creating additional SSL certificates..." createAdditionalSslCertificate
runStep "Updating installation package database..." call "apt-get update"
runStep "Installing vim-gtk..." call "apt-get install vim-gtk -y"
runStep "Installing docker..." installDocker
runStep "Installing docker container owncloud..." installOwnCloud
runStep "Disabling SSH root login..." disableSshRootLogin
runStep "Changing SSH port..." changeSshPort
runStep "Restarting SSH daemon..." call "systemctl restart ssh.service"

saveSettings
echo "Done."
exit 0


