#!/bin/bash

#sshd_config=/etc/ssh/sshd_config
sshd_config=sshd_config
declare -i step
step=1


call()
{
  $2
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
    $2
  fi
  echo ""
  step+=1
}


askYesOrNo()
{
  local answer
  while read -r -p "$1 [y/N]? " answer
  do
    if [ -z $answer ] || [[ $answer = [Nn] ]]
    then
      answer=1
      break
    elif [[ $answer = [Yy] ]]
    then
      answer=0
      break
    fi
  done
  return $answer
}


askInteger()
{
  local answer
  while read -r -p "$1 [1-65535]? " answer
  do
    if [[ $answer =~ ^[0-9][0-9]*$ ]] && [ $answer -gt 0 ] && [ $answer -lt 65535 ]
    then
      break
    fi
  done
  return $answer
}


addUser()
{
  local name
  while read -r -p "Enter username: " name
  do
    if [ ! -z $name ]
    then
      break
    fi
  done
#  call "adduser $name"
  if [ $1 = 1 ]
  then
    echo "Making user a sudo user..."
#    call "usermod -aG sudo $name"
  fi
}


addAdditionalUser()
{
  while askYesOrNo "Do you want to add another user"
  do
    if askYesOrNo "Do you want the user to be a sudo user"
    then
      addUser 1
    else
      addUser 0
    fi
  done
}


disableSshRootLogin()
{
  sed -e 's/^\( *PermitRootLogin .*\)$/#\1/' $sshd_config > $sshd_config.new && mv $sshd_config.new $sshd_config
  echo "PermitRootLogin no" >> $sshd_config
}


changeSshPort()
{
  askInteger "Which port do you want to use for SSH"
  local port=$?
  sed -e 's/^\( *Port .*$\)/#\1/' $sshd_config > $sshd_config.new && mv $sshd_config.new $sshd_config
  echo "Port $port" >> $sshd_config
}


runStep "Changing root password..." #"call passwd"
runStep "Adding main user..." "addUser 1"
runStep "Adding additional users..." "addAdditionalUser"
runStep "Updating installation package database..." #"call apt-get update"
runStep "Installing vim-gtk..." #"call apt-get install vim-gtk -y"
runStep "Installing docker prerequisites..." #"call apt-get install apt-transport-https ca-certificates curl software-properties-common -y"
runStep "Adding docker repository key..." #"call curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -"
runStep "Adding docker repository..." #"call add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable\""
runStep "Updating installation package database for docker..." #"call apt-get update"
runStep "Installing docker..." #"call apt-get install docker-ce -y"
runStep "Installing docker image for redis..." #"call docker pull webhippie/redis"
runStep "Installing docker image for mariadb..." #"call docker pull webhippie/mariadb"
runStep "Installing docker image for owncloud..." #"call docker pull owncloud/server"


runStep "Disabling SSH root login..." "disableSshRootLogin"
runStep "Changing SSH port..." "changeSshPort"
runStep "Restarting SSH daemon..." #"call systemctl restart ssh.service"

echo "Done."
exit 0


