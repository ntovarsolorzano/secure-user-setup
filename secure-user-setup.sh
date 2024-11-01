#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

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
    if grep -q "^$username:" /etc/passwd; then
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
    useradd -m -s /bin/bash "$username"
    
    # Set password
    echo "Setting password for $username"
    passwd "$username"
    
    # Add user to sudo group
    usermod -aG sudo "$username"

    # Copy SSH configuration if it exists
    if [ -d "/home/ubuntu/.ssh" ]; then
        cp -r /home/ubuntu/.ssh /home/"$username"/
        chown -R "$username":"$username" /home/"$username"/.ssh
        chmod 700 /home/"$username"/.ssh
        chmod 600 /home/"$username"/.ssh/*
        echo "SSH configuration copied to new user"
    fi
    
    echo "User $username created successfully with sudo privileges"
    echo "$username" # Return username for later use
    return 0
}

# Function to check if ubuntu user is logged in
check_ubuntu_logged_in() {
    if who | grep -q "^ubuntu "; then
        return 0 # True, ubuntu is logged in
    fi
    return 1 # False, ubuntu is not logged in
}

# Function to remove ubuntu user
remove_ubuntu_user() {
    if id "ubuntu" >/dev/null 2>&1; then
        # Kill any processes owned by ubuntu user
        pkill -u ubuntu || true
        
        # Remove ubuntu user but keep home directory
        deluser ubuntu
        echo "Ubuntu user has been removed successfully (home directory preserved)"
    else
        echo "Ubuntu user does not exist"
    fi
    return 0
}

# Main script execution
echo "=== Secure User Setup ==="
echo "This script will create a new admin user and remove the default 'ubuntu' user."
echo "Please ensure you have a backup method to access the system in case of issues."
echo

# Create new user and store username
new_username=$(create_new_user)

echo
echo "IMPORTANT: Before proceeding:"
read -p "Have you verified you can login as $new_username and use sudo? (y/N): " verified

if [[ $verified =~ ^[Yy]$ ]]; then
    echo
    read -p "Do you want to proceed with removing the ubuntu user? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        while check_ubuntu_logged_in; do
            echo "WARNING: ubuntu user is currently logged in. Please log out the ubuntu user first."
            echo "You can also remove the ubuntu user later by running: sudo deluser ubuntu"
            read -p "Try again? (y/N): " retry
            if [[ ! $retry =~ ^[Yy]$ ]]; then
                echo "Ubuntu user removal skipped"
                exit 0
            fi
        done
        remove_ubuntu_user
    else
        echo "Ubuntu user removal skipped"
        echo "You can remove the ubuntu user later by running: sudo deluser ubuntu"
    fi
else
    echo "Please verify your new user access before removing the ubuntu user"
    echo "You can remove the ubuntu user later by running: sudo deluser ubuntu"
fi

echo
echo "Script completed"
