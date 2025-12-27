#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==========================================
# 1. OS DETECTION & CONFIGURATION
# ==========================================
OS_FAMILY=""
SUDO_GROUP=""
DEL_CMD=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "debian" || "$ID_LIKE" =~ "debian" || "$ID" == "ubuntu" ]]; then
        OS_FAMILY="debian"
        SUDO_GROUP="sudo"
        DEL_CMD="deluser"
        echo "Detected Debian/Ubuntu-based system."
    elif [[ "$ID" == "rhel" || "$ID_LIKE" =~ "rhel" || "$ID" == "fedora" || "$ID" == "centos" || "$ID" == "almalinux" || "$ID" == "rocky" ]]; then
        OS_FAMILY="rhel"
        SUDO_GROUP="wheel"
        DEL_CMD="userdel"
        echo "Detected RHEL/Fedora-based system."
    else
        echo "Unsupported OS family. Proceeding with caution (assuming generic Linux)."
        SUDO_GROUP="wheel" # Fallback
        DEL_CMD="userdel"
    fi
else
    echo "Cannot detect OS. Exiting."
    exit 1
fi

# ==========================================
# 2. IDENTIFY CURRENT USER (To Replace)
# ==========================================
# Attempt to identify the user running sudo (e.g., 'ubuntu', 'ec2-user', 'rocky')
OLD_USER="${SUDO_USER:-ubuntu}" 

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root (or with sudo)"
    exit 1
fi

# Function to validate username
validate_username() {
    local username=$1
    if [[ ! $username =~ ^[a-z][-a-z0-9]*$ ]]; then
        echo "Invalid username. Username must start with a letter and can only contain lowercase letters, numbers, and hyphens."
        return 1
    fi
    if id "$username" >/dev/null 2>&1; then
        echo "Username already exists. Please choose another one."
        return 1
    fi
    return 0
}

# Function to create new user and copy SSH settings
create_new_user() {
    local username=""
    local valid=false

    while [ "$valid" = false ]; do
        read -p "Enter new username: " username
        if validate_username "$username"; then
            valid=true
        fi
    done

    # Create new user
    # -m creates home dir, -s sets shell
    useradd -m -s /bin/bash "$username"
    
    # Set password
    echo "Setting password for $username"
    passwd "$username"
    
    # Add user to the correct admin group (sudo or wheel)
    echo "Adding user to '$SUDO_GROUP' group..."
    usermod -aG "$SUDO_GROUP" "$username"

    # Determine Old User Home Directory
    local old_user_home
    if [ -n "$OLD_USER" ] && id "$OLD_USER" >/dev/null 2>&1; then
        old_user_home=$(eval echo "~$OLD_USER")
    else
        # Fallback if SUDO_USER not set or found, assume /home/ubuntu
        old_user_home="/home/ubuntu"
    fi

    # Copy SSH configuration if it exists
    if [ -d "$old_user_home/.ssh" ]; then
        echo "Copying SSH keys from $old_user_home..."
        mkdir -p /home/"$username"/.ssh
        cp -r "$old_user_home"/.ssh/* /home/"$username"/.ssh/
        chown -R "$username":"$username" /home/"$username"/.ssh
        chmod 700 /home/"$username"/.ssh
        chmod 600 /home/"$username"/.ssh/* || true # Allow failure if directory is empty
        # Ensure authorized_keys specifically is 600
        if [ -f /home/"$username"/.ssh/authorized_keys ]; then
             chmod 600 /home/"$username"/.ssh/authorized_keys
        fi
        echo "SSH configuration copied to new user"
    else
        echo "No SSH configuration found in $old_user_home, skipping copy."
    fi
    
    echo "User $username created successfully with $SUDO_GROUP privileges"
    echo "$username" # Return username for later use
    return 0
}

# Function to check if old user is logged in
check_old_user_logged_in() {
    local user_to_check=$1
    if who | grep -q "^$user_to_check "; then
        return 0 # True, user is logged in
    fi
    return 1 # False, user is not logged in
}

# Function to remove old user
remove_old_user() {
    local user_to_remove=$1
    if id "$user_to_remove" >/dev/null 2>&1; then
        # Kill any processes owned by the user
        pkill -u "$user_to_remove" || true
        
        # Remove user using OS-specific command
        if [ "$DEL_CMD" = "deluser" ]; then
            # Debian way (keeps home by default without --remove-home)
            deluser "$user_to_remove"
        else
            # RHEL/Standard way (keeps home by default)
            userdel "$user_to_remove"
        fi
        
        echo "User '$user_to_remove' has been removed successfully (home directory preserved)"
    else
        echo "User '$user_to_remove' does not exist"
    fi
    return 0
}

# Main script execution
echo "=== Secure User Setup ==="
echo "Target System: $OS_FAMILY (Admin Group: $SUDO_GROUP)"
echo "Current Default User detected as: $OLD_USER"
echo "This script will create a new admin user and remove '$OLD_USER'."
echo "Please ensure you have a backup method to access the system in case of issues."
echo

# Create new user and store username
new_username=$(create_new_user)

echo
echo "IMPORTANT: Before proceeding:"
read -p "Have you verified you can login as $new_username and use sudo? (y/N): " verified

if [[ $verified =~ ^[Yy]$ ]]; then
    echo
    read -p "Do you want to proceed with removing the user '$OLD_USER'? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        
        # Validation to prevent deleting the user you just created
        if [[ "$OLD_USER" == "$new_username" ]]; then
            echo "Error: Cannot delete the user you just created."
            exit 1
        fi

        # Validation to ensure OLD_USER actually exists
        if ! id "$OLD_USER" >/dev/null 2>&1; then
             echo "User $OLD_USER does not exist, nothing to delete."
             exit 0
        fi

        while check_old_user_logged_in "$OLD_USER"; do
            echo "WARNING: $OLD_USER is currently logged in. Please log out that user first."
            echo "You can also remove the user later by running: sudo $DEL_CMD $OLD_USER"
            read -p "Try again? (y/N): " retry
            if [[ ! $retry =~ ^[Yy]$ ]]; then
                echo "User removal skipped"
                exit 0
            fi
        done
        remove_old_user "$OLD_USER"
    else
        echo "User removal skipped"
        echo "You can remove the user later by running: sudo $DEL_CMD $OLD_USER"
    fi
else
    echo "Please verify your new user access before removing the old user"
    echo "You can remove the user later by running: sudo $DEL_CMD $OLD_USER"
fi

echo
echo "Script completed"
