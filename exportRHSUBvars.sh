#! /bin/bash

read -rp $"User to update shell RC file for: " -e rc_user
read -rp $"RH sub username to add to your shell RC file: " -e uname
read -rsp $"RH sub password to add to your shell RC file: " -e pword
echo ''
echo "export RHSUB_USER='$uname'" >> /home/$rc_user/.bashrc
echo "export RHSUB_PASS='$pword'" >> /home/$rc_user/.bashrc
