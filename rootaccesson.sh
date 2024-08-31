#!/bin/bash

# Switch on SSH root access
declare sshdConfig=/etc/ssh/sshd_config
if grep -q -e '^ *PermitRootLogin' $sshdConfig; then
  sed -e 's/^\( *PermitRootLogin\).*$/\1 yes/' -i $sshdConfig
else
  echo "PermitRootLogin yes" >> $sshdConfig
fi
systemctl restart ssh.service
