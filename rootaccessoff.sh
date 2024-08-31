#!/bin/bash

# Switch off SSH root access
declare sshdConfig=/etc/ssh/sshd_config
if grep -q -e '^ *PermitRootLogin' $sshdConfig; then
  sed -e 's/^\( *PermitRootLogin\).*$/\1 no/' -i $sshdConfig
else
  echo "PermitRootLogin no" >> $sshdConfig
fi
systemctl restart ssh.service
