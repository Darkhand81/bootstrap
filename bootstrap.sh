#!/bin/bash

# -------------------------------------------------
# Darkhand's bootstrap script for prepping a fresh install.
# -------------------------------------------------

# Add/remove the base packages you wish to install here:

PACKAGES="\

sudo \
tmux \
htop \
git \
bmon \
avahi-daemon \
iptables \
fail2ban\

"
# -------------------------------------------------

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "$0 is not running as root. Try using sudo."
    exit 2
fi

# Ensure whiptail is installed, and install it if not
if [ $(dpkg-query -W -f='${Status}' whiptail 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
  apt-get install whiptail -y;
fi

# Get username to create and setup
function getUsername() {
  NAME=$(whiptail --title "Create user" --inputbox "Enter username to create:" 0 0 3>&1 1>&2 2>&3)
    exitstatus=$?
      [[ "$exitstatus" = 1 ]] && exit;
}

# Set password
function getPassword() {
  PASSWORD1=$(whiptail --title "Create password" --inputbox "Please enter a password for user $NAME:" 0 0 3>&1 1>&2 2>&3)
    exitstatus=$?
      [[ "$exitstatus" = 1 ]] && exit;

  PASSWORD2=$(whiptail --title "Create password" --inputbox "Please re-enter your password:" 0 0 3>&1 1>&2 2>&3)
    exitstatus=$?
      [[ "$exitstatus" = 1 ]] && exit;

    if [ $PASSWORD1 != $PASSWORD2 ] 
      then
        whiptail --ok-button Retry --msgbox "Passwords do mot match!" 0 0
        getPassword
      else
        return
    fi
}

# Run the functions
getUsername
getPassword

# Set root shell to bash
chsh -s /bin/bash

#Create user and set default shell
useradd -s /bin/bash -m $NAME && passwd $PASSWORD1

#Add user to sudoers
usermod -a -G sudo $NAME

#.bashrc additions
echo "alias ll='ls -lh'" >> /home/$NAME/.bashrc
echo "alias la='ls -alh'" >> /home/$NAME/.bashrc
echo "alias ll='ls -lh'" >> /home/$NAME/.bashrc
echo "force_color_prompt=yes" >> /home/$NAME/.bashrc

# Install basic packages with a pretty progress bar
{
  i=1
    while read -r line; do
      i=$(( i + 1 ))
      echo $i
      done < <(apt-get -s install $PACKAGES -y)
} | whiptail --title "Progress" --gauge "Installing basic packages..." 6 60 0

# Optionally install build-essential
if whiptail --yesno --defaultno "Install build-essential?" 0 0 ;then
  {
    i=1
    while read -r line; do
      i=$(( i + 1 ))
      echo $i
      done < <(apt-get -s install build-essential -y)
   } | whiptail --title "Progress" --gauge "Installing build essentials..." 6 60 0
  else
    return
fi

whiptail --title "Done!" --msgbox "Setup complete!\n\n - Set root shell to bash\n - User $NAME created\n - Added $NAME to sudoers file\n - Added ll/la aliases\n - Installed packages: $PACKAGES" 0 0

echo "Setup complete, enjoy!"
