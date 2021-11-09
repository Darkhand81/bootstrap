#!/bin/bash

# My set of stuff to run at install time!
# Run as root or sudo

#Install basics
apt install sudo tmux htop git bmon avahi-daemon iptables fail2ban #build-essential

#Add paul to sudoers
usermod -a -G sudo paul

#.bashrc additions
echo "alias ll='ls -lh'" >> /home/paul/.bashrc
echo "alias la='ls -alh'" >> /home/paul/.bashrc
echo "alias ll='ls -lh'" >> /home/paul/.bashrc
echo "force_color_prompt=yes" >> /home/paul/.bashrc
