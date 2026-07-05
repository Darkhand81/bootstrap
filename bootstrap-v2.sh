#!/bin/bash

# ---------------------------------------------------------
# Darkhand's bootstrap script for prepping a fresh install.
# Version 2 - 07-05-26
# ---------------------------------------------------------

set -u

# --------------
# Configuration
# --------------

# Add/remove the base packages you wish to install here:
PACKAGES=(
  sudo
  rsyslog
  isc-dhcp-client
  tmux
  htop
  curl
  wget
  git
  bmon
  iptables
  rsync
  pv
)

# Network that is allowed to log in as root over SSH:
SSH_ALLOWED_NET="192.168.1.0/24"

# Where to download the decompress helper script from:
DECOMPRESS_URL="https://raw.githubusercontent.com/Darkhand81/decompress/main/decompress.sh"

# All command output is logged here for troubleshooting:
LOGFILE="/var/log/bootstrap.log"

# Keep apt from stopping to ask questions mid-install (conffile prompts
# would be invisible behind the progress gauge and hang the script)
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# ----------
# Functions
# ----------

# Run a command inside a whiptail progress gauge. Progress is estimated
# from the command's output lines and capped at 99% until the command
# finishes, so the bar can't overshoot. All output goes to $LOGFILE.
# Usage: runWithGauge "Message..." command [args...]
# Returns the command's exit status.
runWithGauge() {
  local message="$1" rcfile rc
  shift
  rcfile=$(mktemp)
  {
    local i=0
    while IFS= read -r line; do
      printf '%s\n' "$line" >> "$LOGFILE"
      [ "$i" -lt 99 ] && i=$(( i + 1 ))
      echo "$i"
    done < <("$@" 2>&1; echo "$?" > "$rcfile")
    echo 100
  } | whiptail --title "Progress" --gauge "$message" 6 60 0
  rc=$(cat "$rcfile" 2>/dev/null || echo 1)
  rm -f "$rcfile"
  return "$rc"
}

# Prompt for a username and drive the user creation/configuration flow.
# Cancelling the username prompt skips user setup entirely; cancelling
# the password prompt returns here rather than aborting the script.
setupUser() {
  while true; do
    NAME=$(whiptail --title "Create user" --cancel-button "Skip" --inputbox "Enter username to create:" 0 0 3>&1 1>&2 2>&3) || return 0
    if [ -z "$NAME" ]; then
      whiptail --ok-button Retry --msgbox "Username cannot be empty!" 0 0
      continue
    fi
    if id "$NAME" &>/dev/null; then
      if whiptail --yesno "User $NAME already exists. Continue setting up this user?" 0 0; then
        configureUser
        return 0
      fi
      # Answered no: ask for a different username
    else
      if getPassword; then
        createUser && configureUser
        return 0
      fi
      # Password entry cancelled: ask for the username again (or Skip)
    fi
  done
}

# Prompt for a password (hidden input) until both entries match.
# Returns nonzero if the user cancels.
getPassword() {
  while true; do
    PASSWORD1=$(whiptail --title "Create password" --passwordbox "Please enter a password for user $NAME:" 0 0 3>&1 1>&2 2>&3) || return 1
    PASSWORD2=$(whiptail --title "Create password" --passwordbox "Please re-enter your password:" 0 0 3>&1 1>&2 2>&3) || return 1

    if [ -z "$PASSWORD1" ]; then
      whiptail --ok-button Retry --msgbox "Password cannot be empty!" 0 0
    elif [ "$PASSWORD1" != "$PASSWORD2" ]; then
      whiptail --ok-button Retry --msgbox "Passwords do not match!" 0 0
    else
      return 0
    fi
  done
}

# Create the user with bash as their shell and set their password
createUser() {
  if useradd -s /bin/bash -m "$NAME" >>"$LOGFILE" 2>&1 &&
     printf '%s:%s\n' "$NAME" "$PASSWORD1" | chpasswd >>"$LOGFILE" 2>&1; then
    createdUser=1
  else
    whiptail --title "Error" --msgbox "Failed to create user $NAME! See $LOGFILE for details." 0 0
    return 1
  fi
}

# A helper function to uncomment a config file line or add it if it doesn't exist (used for .bashrc additions)
addOrUncommentLine() {
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

configureUser() {
  # Add user to the sudo group
  usermod -a -G sudo "$NAME"

  # Require no password for sudo commands. Written to a temp file and
  # validated first: a malformed sudoers.d file can lock sudo entirely.
  local sudoersFile="/etc/sudoers.d/sudoer_$NAME" tmpSudoers
  tmpSudoers=$(mktemp)
  echo "$NAME ALL=(ALL) NOPASSWD: ALL" > "$tmpSudoers"
  chmod 0440 "$tmpSudoers"
  if visudo -cf "$tmpSudoers" >>"$LOGFILE" 2>&1; then
    cp "$tmpSudoers" "$sudoersFile"
    chmod 0440 "$sudoersFile"
  else
    whiptail --title "Error" --msgbox "Generated sudoers entry failed validation and was NOT installed. See $LOGFILE." 0 0
  fi
  rm -f "$tmpSudoers"

  # .bashrc additions
  local bashrcFile="/home/$NAME/.bashrc"
  addOrUncommentLine "alias ll=" "alias ll='ls -lh'" "$bashrcFile"
  addOrUncommentLine "alias la=" "alias la='ls -alh'" "$bashrcFile"
  addOrUncommentLine "force_color_prompt=" "force_color_prompt=yes" "$bashrcFile"

  # Copy the modified .bashrc to /root/.bashrc, since we want these modifications when logged in as root as well
  cp "$bashrcFile" /root/.bashrc
}

# Enable the non-free component (needed for steamcmd), handling both the
# classic one-line /etc/apt/sources.list format and the deb822 .sources
# format used by fresh Debian 12+ installs. Idempotent: lines that
# already list non-free are left alone. (The pattern deliberately
# requires a space or end-of-line after "non-free" so it doesn't match
# the separate non-free-firmware component.)
enableNonFree() {
  if [ -s /etc/apt/sources.list ]; then
    if ! grep -Eq '^(deb|deb-src) .*non-free( |$)' /etc/apt/sources.list; then
      cp /etc/apt/sources.list /etc/apt/sources.list.backup
      sed -i -E '/^(deb|deb-src) /{/ non-free( |$)/!s/$/ non-free/}' /etc/apt/sources.list
    fi
  fi

  local f
  for f in /etc/apt/sources.list.d/*.sources; do
    [ -e "$f" ] || continue
    if grep -q '^Components:' "$f" && ! grep -Eq '^Components:.* non-free( |$)' "$f"; then
      cp "$f" "$f.backup"
      sed -i -E '/^Components:/{/ non-free( |$)/!s/$/ non-free/}' "$f"
    fi
  done
}

# Allow root SSH login from $SSH_ALLOWED_NET only. Uses a sshd_config.d
# drop-in when available, and validates the config before restarting so
# a bad config can't take down SSH on a remote box.
configureSSH() {
  local marker="Match Address $SSH_ALLOWED_NET"
  local dropin="/etc/ssh/sshd_config.d/50-bootstrap-root-login.conf"

  # Already configured (either style)? Nothing to do.
  if grep -qsF "$marker" "$dropin" /etc/ssh/sshd_config; then
    return 0
  fi

  local target
  if [ -d /etc/ssh/sshd_config.d ]; then
    target="$dropin"
    {
      echo "# Allow root login only from the local network"
      echo "$marker"
      echo "    PermitRootLogin yes"
      # Drop-ins are included at the TOP of sshd_config, so reset the
      # match context or the rest of the main config would only apply
      # to connections from this network.
      echo "Match All"
    } > "$target"
  else
    target=/etc/ssh/sshd_config
    {
      echo ""
      echo "# Allow root login only from the local network"
      echo "$marker"
      echo "    PermitRootLogin yes"
    } >> "$target"
  fi

  if sshd -t >>"$LOGFILE" 2>&1; then
    systemctl restart ssh
  else
    whiptail --title "Error" --msgbox "sshd config validation failed; NOT restarting SSH. Review $target and $LOGFILE." 0 0
  fi
}

# -------------------------------------------------
# Start
# -------------------------------------------------

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "$0 is not running as root. Try using sudo."
    exit 2
fi

createdUser=0
NAME=""

echo "=== bootstrap run $(date) ===" >> "$LOGFILE"

# Update the package list BEFORE installing anything - on a fresh
# install the shipped lists may be stale and installs would 404.
# whiptail isn't guaranteed to exist yet, so this one runs in plain text.
echo "Updating package list..."
apt-get update >>"$LOGFILE" 2>&1

# Ensure prerequisites are installed (sudo is needed early for visudo
# validation during user setup)
for pkg in apt-utils whiptail sudo; do
  if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
    echo "Installing $pkg before continuing..."
    apt-get install "${APT_OPTS[@]}" "$pkg" >>"$LOGFILE" 2>&1
  fi
done

# Upgrade packages
runWithGauge "Upgrading existing packages..." apt-get upgrade "${APT_OPTS[@]}" ||
  whiptail --title "Warning" --msgbox "Package upgrade reported errors. See $LOGFILE. Continuing." 0 0

# Request username setup
setupUser

# Set root shell to bash
chsh -s /bin/bash root

# Optionally change timezone
CURRENT_TZ=$(cat /etc/timezone 2>/dev/null)
if [ -z "$CURRENT_TZ" ]; then
  CURRENT_TZ=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
fi
if whiptail --yesno --defaultno "Timezone is currently ${CURRENT_TZ:-unknown}. Change?" 0 0; then
  dpkg-reconfigure --frontend dialog tzdata
  whiptail --title "Complete" --msgbox "Timezone updated!" 0 0
fi

# Optionally install build-essential
if whiptail --yesno --defaultno "Install build-essential?" 0 0; then
  if runWithGauge "Installing build-essential..." apt-get install "${APT_OPTS[@]}" build-essential; then
    whiptail --title "Complete" --msgbox "build-essential packages installed!" 0 0
  else
    whiptail --title "Error" --msgbox "build-essential install failed! See $LOGFILE. Continuing." 0 0
  fi
fi

# Optionally install SteamCmd
if whiptail --yesno --defaultno "Install SteamCmd?" 0 0; then
  # Add i386 architecture
  dpkg --add-architecture i386

  # Enable the non-free component (backs up the files it touches)
  enableNonFree

  # Suppress non-free firmware warnings
  echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' > /etc/apt/apt.conf.d/no-nonfree-warnings.conf

  runWithGauge "Updating package list..." apt-get update

  # Pre-accept Steamcmd license and EULA:
  echo steam steam/license note '' | debconf-set-selections
  echo steam steam/purge note '' | debconf-set-selections
  echo steam steam/question select "I AGREE" | debconf-set-selections

  runWithGauge "Installing SteamCmd..." apt-get install "${APT_OPTS[@]}" steamcmd ||
    whiptail --title "Error" --msgbox "SteamCmd install failed! See $LOGFILE. Continuing." 0 0
fi

# Install basic packages
runWithGauge "Installing basic packages..." apt-get install "${APT_OPTS[@]}" "${PACKAGES[@]}" ||
  whiptail --title "Warning" --msgbox "Some packages failed to install. See $LOGFILE. Continuing." 0 0

# Install decompress script and set executable (after the package
# install above so curl is guaranteed to be present)
if curl -fsSL -o /usr/local/bin/decompress "$DECOMPRESS_URL" 2>>"$LOGFILE"; then
  chmod +x /usr/local/bin/decompress
else
  whiptail --title "Error" --msgbox "Decompress script download failed! Continuing." 0 0
fi

# Change GRUB timeout at boot to 1 second if not already set
# (skipped on systems without GRUB, e.g. WSL or containers)
if [ -f /etc/default/grub ] && command -v update-grub >/dev/null 2>&1; then
  if ! grep -Eq '^GRUB_TIMEOUT=1$' /etc/default/grub; then
    sed -i -E 's/^(GRUB_TIMEOUT=)[0-9]+$/\11/' /etc/default/grub
    runWithGauge "Updating GRUB timeout..." update-grub
  fi
fi

# Configure SSH to allow root login only from the local network
configureSSH

# If we're running on WSL, allow ping without superuser privileges
# (/proc/sys/fs/binfmt_misc/WSLInterop normally only exists when running on WSL)
if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] && command -v setcap >/dev/null 2>&1; then
    setcap cap_net_raw+ep /bin/ping
fi

# Print exit message depending on what we did, based on the value of $createdUser
if [ "$createdUser" -eq 1 ]; then
  USERLINES=" - User $NAME created\n - Added $NAME to sudoers file\n - Added ll/la aliases\n"
else
  USERLINES=""
fi
whiptail --title "Done!" --msgbox "Setup complete!\n\n - Updated package list\n - Upgraded all packages\n - Set root shell to bash\n$USERLINES - Installed decompress script\n - Updated GRUB timeout\n - Allowed root login from $SSH_ALLOWED_NET\n - Installed packages: ${PACKAGES[*]}" 0 0

echo "Setup complete, enjoy! (log: $LOGFILE)"
