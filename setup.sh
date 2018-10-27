#!/bin/bash

#sshd_config=/etc/ssh/sshd_config
sshd_config=sshd_config


call()
{
  if [ ! -z "$1" ]
  then
    echo $1
  fi
  if [ ! -z "$2" ]
  then
    $2
  fi
  if [ $? -gt 0 ]
  then
    exit $?
  fi
  echo ""
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
  call "" #adduser $name
  if [ $1 = 1 ]
  then
    echo "Making user a sudo user..."
    call "" #usermod -aG sudo $name
  fi
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


changeRootPassword()
{
  call "1. Changing root password..." #"passwd"
}


addMainUser()
{
  echo "2. Adding main user..."
  addUser 1
}


addAdditionalUser()
{
  while askYesOrNo "3. Do you want to add another user"
  do
    if askYesOrNo "Do you want the user to be a sudo user"
    then
      addUser 1
    else
      addUser 0
    fi
  done
  echo ""
}


updatePackageDatabase()
{
  call "4. Updating installation package database..." #"apt-get update"
}


installVim()
{
  call "5. Installing vim-gtk..." #"apt-get install vim-gtk -y"
}


installDockerPrerequisites()
{
  call "6. Installing docker prerequisites..." #"apt-get install apt-transport-https ca-certificates curl software-properties-common -y"
}


addingDockerRepositoryKey()
{
  call "7. Adding docker repository key..." #"curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -"
}


addingDockerRepository()
{
  call "8. Adding docker repository..." #"add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable\""
}


updatePackageDatabaseDocker()
{
  call "9. Updating installation package database for docker..." #"apt-get update"
}


installDocker()
{
  call "10. Installing docker..." #"apt-get install docker-ce -y"
}


installOwncloud()
{
  call "11. Installing owncloud..." #"docker pull owncloud/server"
}


disableSshRootLogin()
{
  echo "97. Disabling SSH root login..."
  sed -e 's/^\( *PermitRootLogin .*\)$/#\1/' $sshd_config > $sshd_config.new && mv $sshd_config.new $sshd_config
  echo "PermitRootLogin no" >> $sshd_config
  echo ""
}


changeSshPort()
{
  echo "98. Changing SSH port..."
  askInteger "Which port do you want to use for SSH"
  local port=$?
  sed -e 's/^\( *Port .*$\)/#\1/' $sshd_config > $sshd_config.new && mv $sshd_config.new $sshd_config
  echo "Port $port" >> $sshd_config
  echo ""
}


restartSSh()
{
  call "99. Restarting SSH daemon..." #"systemctl restart ssh.service"
}


changeRootPassword
addMainUser
addAdditionalUser
updatePackageDatabase
installVim
installDockerPrerequisites
addingDockerRepositoryKey
addingDockerRepository
updatePackageDatabaseDocker
installDocker
installOwncloud



disableSshRootLogin
changeSshPort
restartSSh

echo "Done."
exit 0


