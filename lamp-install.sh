#!/bin/bash

# Linux, Apache, MySQL, PHP (LAMP) Server Install
LOG_FILE="$HOME/lamp_setup.log"

# Function to log messages to a file
log_message() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" >>"$LOG_FILE"
}

# Function to wait for a command to finish
wait_command() {
    "$@" && wait
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_message "Error: Command '$*' failed with exit code $exit_code"
        exit $exit_code
    fi
}

# Log script start
log_message "LAMP server setup script started."

sudo apt-get update && sudo apt full-upgrade -y
wait_command sudo apt-get install apache2 -y
wait_command sudo systemctl enable apache2 
user_name=$(whoami)
sudo usermod -aG www-data $user_name

# Update system and install packages
wait_command sudo apt-get install expect git wget curl -y
wait_command sudo apt-get install php php-xml php-common php-curl php-mysql php-xdebug php-db php-sqlite3 libapache2-mod-php php-mbstring php-gd -y

php_v=$(php -r "echo PHP_VERSION;" | awk -F. '{print $1"."$2}')

wait_command sudo apt install mysql-server -y
TEMP_FILE=$(mktemp)
echo -e "n\ny\ny\ny" >"$TEMP_FILE"
printf "n\ny\ny\ny\ny\ny\ny\n" | sudo mysql_secure_installation
wait_command rm "$TEMP_FILE"

TARGET_DIRECTORY="/var/www"

user_name=$(whoami)
sudo chown -R $user_name:$user_name $TARGET_DIRECTORY
sudo chmod -R 755 "$TARGET_DIRECTORY"
sudo find "$TARGET_DIRECTORY" -type f -exec chmod 644 {} \;

# Create phpinfo file
echo -e "<?php\nphpinfo();\n?>" | tee /var/www/html/info.php

s_name=$(hostname)
echo "ServerName $s_name" | sudo tee -a /etc/apache2/apache2.conf

# Edits apache2.conf to look for index.php websites first.
echo -e "<IfModule mod_dir.c>\nDirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm\n</IfModule>" | sudo tee /etc/apache2/mods-enabled/dir.conf

# Reload Apache
wait_command sudo systemctl reload apache2

# Log script end
log_message "LAMP server setup script completed successfully."



