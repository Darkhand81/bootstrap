#!/bin/bash

# ---------------------------------------------------------
# Darkhand's bootstrap script for prepping a fresh install.
# Version 01-21-24
# ---------------------------------------------------------

# Add/remove the base packages you wish to install here:

PACKAGES="\

sudo \
tmux \
htop \
git \
bmon \
avahi-daemon \
iptables \
rsync \
pv \
fail2ban\

"
# ----------
# Functions
# ----------

# Get username to create and setup
function getUsername() {
  createdUser=0
  NAME=$(whiptail --title "Create user" --cancel-button "Skip" --inputbox "Enter username to create:" 0 0 3>&1 1>&2 2>&3)
    exitstatus=$?
      if [ "$exitstatus" = 0 ]; then
        # Check if user already exists
        if id "$NAME" &>/dev/null; then
          #whiptail --title Error --ok-button Retry --msgbox "User already exists!" 0 0
          #getUsername
          if whiptail --yesno "User already exists. Continue setting up user $NAME?" 0 0 ;then
            configureUser
          else
            getUsername
          fi
        else
          # User not found, ok to create user and set a password
          getPassword
        fi
      fi
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
        # Username is created, so it's safe to run the configurations
        configureUser
    fi
}

# A helper function to uncomment a config file line or add it if it doesn't exist (used for .bashrc additions)
function addOrUncommentLine() {
  local pattern="$1"
  local newLine="$2"
  local file="$3"

  # Check if the line exists in any form (commented or uncommented)
  if grep -qE "$pattern" "$file"; then
    # Line exists, replace it with the new line
    sed -i "/$pattern/c\\$newLine" "$file"
  else
    # Line does not exist, add the new line
    echo "$newLine" >> "$file"
  fi
}

function configureUser() {
  # Create user (if they don't already exist) and set default shell
  if ! id "$NAME" >/dev/null 2>&1
    then
      # User does not exist, create them
      useradd -s /bin/bash -m $NAME
      echo $NAME:$PASSWORD1 | chpasswd
      createdUser=1
    else
    # User already exists, do nothing"
    true
  fi

  # Add user to sudoers
  usermod -a -G sudo $NAME
  
  #Require no password for sudo commands
  echo "$NAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/sudoer_$NAME

  # .bashrc additions
  BASHRC_FILE="/home/$NAME/.bashrc"
  addOrUncommentLine "alias ll=" "alias ll='ls -lh'" "$BASHRC_FILE"
  addOrUncommentLine "alias la=" "alias la='ls -alh'" "$BASHRC_FILE"
  addOrUncommentLine "force_color_prompt=" "force_color_prompt=yes" "$BASHRC_FILE"
}

# -------------------------------------------------
# Start
# -------------------------------------------------

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "$0 is not running as root. Try using sudo."
    exit 2
fi

# Ensure prerequisites are installed, and install them if not
# apt-utils
if [ $(dpkg-query -W -f='${Status}' apt-utils 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
  echo "Installing apt-utils before continuing..."
  apt-get install apt-utils -y > /dev/null;
fi

# whiptail
if [ $(dpkg-query -W -f='${Status}' whiptail 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
  echo "Installing whiptail before continuing..."
  apt-get install whiptail -y > /dev/null;
fi

# Update package list
{
  i=1
    while read -r line; do
      i=$(( i + 1 ))
      echo $i
      done < <(apt-get update)
} | whiptail --title "Progress" --gauge "Updating package list..." 6 60 0

# Upgrade packages
{
  i=1
    while read -r line; do
      i=$(( i + 1 ))
      echo $i
      done < <(apt-get upgrade -y)
} | whiptail --title "Progress" --gauge "Upgrading existing packages..." 6 60 0

# Request username setup
getUsername

# Set root shell to bash
chsh -s /bin/bash

# Optionally change timezone
if whiptail --yesno --defaultno "Timezone is currently $(cat /etc/timezone). Change?" 0 0 ;then
  dpkg-reconfigure tzdata
  whiptail --title "Complete" --msgbox "Timezone updated!" 0 0
fi

# Optionally install build-essential
if whiptail --yesno --defaultno "Install build-essential?" 0 0 ;then
  {
    i=1
    while read -r line; do
      i=$(( i + 1 ))
      echo $i
      done < <(apt-get install build-essential -y)
  } | whiptail --title "Progress" --gauge "Installing build-essential..." 6 60 0
  whiptail --title "Complete" --msgbox "build-essential packages installed!" 0 0
fi

# Optionally install SteamCmd
if whiptail --yesno --defaultno "Install SteamCmd?" 0 0 ;then
  echo "Installing SteamCmd..."

  # Add i386 architecture
  dpkg --add-architecture i386

  # Backup the sources.list file
  cp /etc/apt/sources.list /etc/apt/sources.list.backup

  # Add 'non-free' to each repository entry
  sed -i 's/\(deb\|deb-src\) \([^ ]* [^ ]*\)/\1 \2 non-free/g' /etc/apt/sources.list

  # Create a configuration file to suppress non-free firmware warnings
  echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' > /etc/apt/apt.conf.d/no-nonfree-warnings.conf

  # Update package list with progress bar
  {
    i=1
    while read -r line; do
      i=$(( i + 10 ))  # Increment progress
      echo $i
    done < <(apt-get update)
  } | whiptail --title "Progress" --gauge "Updating package list..." 6 60 0

  # Pre-accept Steamcmd license and EULA:
  echo steam steam/license note '' | sudo debconf-set-selections
  echo steam steam/purge note '' | sudo debconf-set-selections
  echo steam steam/question select "I AGREE" | sudo debconf-set-selections

  # Install Steamcmd package
  {
    i=1
    while read -r line; do
      i=$(( i + 10 ))  # Increment progress
      echo $i
    done < <(apt-get install steamcmd -y)
  } | whiptail --title "Progress" --gauge "Installing SteamCmd..." 6 60 0

  whiptail --title "Complete" --msgbox "SteamCmd installed!" 0 0
fi

# Install basic packages
{
  i=1
    while read -r line; do
      i=$(( i + 1 ))
      echo $i
      done < <(apt-get install $PACKAGES -y)
} | whiptail --title "Progress" --gauge "Installing basic packages..." 6 60 0


#Print exit message depending on what we did, based on the value of $createdUser
if [ "$createdUser" -eq 1 ]; then
  whiptail --title "Done!" --msgbox "Setup complete!\n\n - Updated package list\n - Upgraded all packages\n - Set root shell to bash\n - User $NAME created\n - Added $NAME to sudoers file\n - Added ll/la aliases\n - Installed packages: $PACKAGES" 0 0
else
  whiptail --title "Done!" --msgbox "Setup complete!\n\n - Updated package list\n - Upgraded all packages\n - Set root shell to bash\n - Installed packages: $PACKAGES" 0 0
fi

echo "Setup complete, enjoy!"

