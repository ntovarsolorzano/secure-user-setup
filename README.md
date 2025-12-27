# secure-user-setup
I work frequently on the Cloud VMs. Default machines have pre-installed the ubuntu user, which is unsecure, it is a known username. So, here is a bash script that asks the user to create, creates such user with sudo privileges, and afterwards, deletes the ubuntu user.

# Running it
Run 

`sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ntovarsolorzano/secure-user-setup/main/secure-user-setup.sh)"`

or

`sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ntovarsolorzano/secure-user-setup/main/secure-user-setup-all-one-v1.sh)"`

1. The ubuntu folder won't be delete, just the user.
2. If you are connected through SSH using `ubuntu`, you may get an error.
