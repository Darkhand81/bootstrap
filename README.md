# bootstrap
My initial setup script for fresh Debian installs. Get all the annoying basics out of the way with pretty interactive dialogs:

- Update package list
- Upgrade existing packages
- Set root shell to bash
- Install regularly used packages:
  - sudo
  - tmux
  - htop
  - git
  - bmon
  - avahi-daemon
  - iptables
  - fail2ban
- Optionally install build-essential
- Create initial user and set password
- Add user to sudeoers file
- Add .bashrc aliases for ll/la commands

