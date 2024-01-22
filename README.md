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
  - rsync
  - pv
  - fail2ban
- Optionally install build-essential
- Optionally set timezone
- Optionally install steamcmd
- Create initial user and set password
- Add user to sudoers file
- Add user to sudoers.d to require no password with sudo commands
- Add .bashrc aliases for ll/la commands
- Enable color prompts
