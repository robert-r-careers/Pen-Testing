#!/bin/bash

MYSQL_DATABASES=("dvwa" "sqlilabs" "mutillidae" "bWAPP")
LOG_FILE="$HOME/lamp_setup.log"

log_message() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

wait_command() {
    "$@" && wait
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_message "Error: Command '$*' failed with exit code $exit_code"
        # Continue with the script instead of immediate exit
    fi
}

create_mysql_user() {
    wait_command sudo mysql -e "CREATE USER IF NOT EXISTS '$1'@'localhost' IDENTIFIED BY '$2';"
    wait_command sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$1'@'localhost' WITH GRANT OPTION;"
    wait_command sudo mysql -e "FLUSH PRIVILEGES;"
}

echo "Let's create a MySQL user account and databases."

# Prompt the user for the database
echo "Select a database to create:"
select MYSQL_DATABASE_CHOICE in "${MYSQL_DATABASES[@]}"; do
    case $MYSQL_DATABASE_CHOICE in
        "dvwa" | "sqlilabs" | "mutillidae" | "bWAPP")
            break
            ;;
        *)
            echo "Invalid choice. Please select a valid database."
            ;;
    esac
done

MYSQL_USER="PenLabs"
MYSQL_PASSWORD="Password1!"
MYSQL_DATABASE="$MYSQL_DATABASE_CHOICE"

# Create MySQL user if it doesn't exist
existing_user=$(sudo mysql -se "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$MYSQL_USER')")
[ "$existing_user" -ne 1 ] && create_mysql_user "$MYSQL_USER" "$MYSQL_PASSWORD"

# Create MySQL database if it doesn't exist
existing_db=$(sudo mysql -e "SHOW DATABASES LIKE '$MYSQL_DATABASE'")
if [ -z "$existing_db" ]; then
    log_message "MySQL database '$MYSQL_DATABASE' does not exist. Creating it."
    wait_command sudo mysql -e "CREATE DATABASE $MYSQL_DATABASE;"
    log_message "MySQL database '$MYSQL_DATABASE' created successfully."
else
    log_message "MySQL database '$MYSQL_DATABASE' already exists. Continuing with the script."
fi

# Rest of your script...

# Continue with DVWA installation and configuration if the chosen database is 'dvwa'
if [ "$MYSQL_DATABASE" == "dvwa" ]; then
    TARGET_DIRECTORY="/var/www/dvwa.com"
    REPO_URL="https://github.com/digininja/DVWA.git"
    TEMP_CLONE_DIRECTORY="/tmp/$MYSQL_DATABASE-temp-clone"
    APACHE_SITE_CONF="$MYSQL_DATABASE.com.conf"
    CONF_PATH="/etc/apache2/sites-available/$APACHE_SITE_CONF"

    # Create the config content
    CONFIG_CONTENT=$(
        cat <<-EOL
# Create and save a config file for each of your sites
# filename format: "$APACHE_SITE_CONF" , Path: "$CONF_PATH"
# enable site command: a2ensite $APACHE_SITE_CONF

<Directory $TARGET_DIRECTORY>
    Require all granted
</Directory>
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $TARGET_DIRECTORY
    ServerName $MYSQL_DATABASE.com
    ServerAlias www.$MYSQL_DATABASE.com
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOL
    )

    # Create the config file
    echo "$CONFIG_CONTENT" | sudo tee "$CONF_PATH" # Use tee to write with sudo permissions
    mkdir -p $TARGET_DIRECTORY
    chown_user_name=$(whoami)
    sudo chown -R $chown_user_name:$chown_user_name "$TARGET_DIRECTORY"

    # Clone the repository to a temporary directory
    wait_command git clone "$REPO_URL" "$TEMP_CLONE_DIRECTORY"

    # Move only the contents of the clone to the specified directory
    wait_command rsync -av "$TEMP_CLONE_DIRECTORY/" "$TARGET_DIRECTORY"

    # Remove the temporary clone directory
    wait_command rm -rf "$TEMP_CLONE_DIRECTORY"

    # Make folders writable
    wait_command sudo find "$TARGET_DIRECTORY" -type d -exec chmod 755 {} \;
    wait_command sudo find "$TARGET_DIRECTORY" -type f -exec chmod 644 {} \;

# Check if the configuration file already exists
config_file="$TARGET_DIRECTORY/config/config.inc.php"
if [ ! -f "$config_file" ]; then
    wait_command cp "$TARGET_DIRECTORY/config/config.inc.php.dist" "$config_file"
fi

# Display the contents with line numbers
grep -vn cat "$config_file" >/dev/null 2>&1

# Modify the values in lines for the first config file
line_num_database=19
line_num_user=20
line_num_password=21

wait_command sed -i "${line_num_database}s/.*/\$_DVWA[ 'db_database' ] = '$MYSQL_DATABASE';/" "$config_file"
wait_command sed -i "${line_num_user}s/.*/\$_DVWA[ 'db_user' ]     = '$MYSQL_USER';/" "$config_file"
wait_command sed -i "${line_num_password}s/.*/\$_DVWA[ 'db_password' ] = '$MYSQL_PASSWORD';/" "$config_file"

# Modify the values in lines for the additional config file
line_num_display_errors=503
line_num_startup_errors=512
line_num_allow_url_include=865
line_num_allow_url_fopen=861

php_v=$(php -r "echo PHP_VERSION;" | awk -F. '{print $1"."$2}')
another_config_file="/etc/php/$php_v/apache2/php.ini"

# Check if the php.ini file exists
if [ ! -f "$another_config_file" ]; then
    log_message "Error: PHP configuration file not found."
    exit 1
fi

# Modify the values in php.ini
wait_command sudo sed -i "${line_num_display_errors}s/.*/display_errors = On/" "$another_config_file"
wait_command sudo sed -i "${line_num_startup_errors}s/.*/display_startup_errors = On/" "$another_config_file"
wait_command sudo sed -i "${line_num_allow_url_include}s/.*/allow_url_include = On/" "$another_config_file"
wait_command sudo sed -i "${line_num_allow_url_fopen}s/.*/allow_url_fopen = On/" "$another_config_file"

# Make folders writable
wait_command sudo chmod -R 777 "$TARGET_DIRECTORY/hackable/uploads/"
wait_command sudo chmod -R 777 "$TARGET_DIRECTORY/config/"

    # Enable the site in Apache
    wait_command sudo a2ensite "$APACHE_SITE_CONF"
    wait_command sudo a2dissite 000-default
    sudo systemctl reload apache2

    echo
    echo "Edit 'IP, DomainName, and DomainAlias' in the /etc/hosts file on the HOST computer. \
    Below line '127.0.1.1 your_hostname'  \
    add the following line: \
    your_server_IP www.$MYSQL_DATABASE.com $MYSQL_DATABASE.com \
    This will allow you to access the site by www.$MYSQL_DATABASE.com in your local browser."

    log_message "DVWA installation and configuration completed successfully."
fi

if [ "$MYSQL_DATABASE" == "mutillidae" ]; then
    TARGET_DIRECTORY="/var/www/mutillidae.com"
    REPO_URL="https://github.com/webpwnized/mutillidae.git"
    TEMP_CLONE_DIRECTORY="/tmp/$MYSQL_DATABASE-temp-clone"
    APACHE_SITE_CONF="$MYSQL_DATABASE.com.conf"
    CONF_PATH="/etc/apache2/sites-available/$APACHE_SITE_CONF"

    # Create the config content
    CONFIG_CONTENT=$(
        cat <<-EOL
# Create and save a config file for each of your sites
# filename format: "$APACHE_SITE_CONF" , Path: "$CONF_PATH"
# enable site command: a2ensite $APACHE_SITE_CONF

<Directory $TARGET_DIRECTORY>
    Require all granted
</Directory>
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $TARGET_DIRECTORY
    ServerName $MYSQL_DATABASE.com
    ServerAlias www.$MYSQL_DATABASE.com
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOL
    )

    # Create the config file
    echo "$CONFIG_CONTENT" | sudo tee "$CONF_PATH" # Use tee to write with sudo permissions
    mkdir -p $TARGET_DIRECTORY
    chown_user_name=$(whoami)
    sudo chown -R $chown_user_name:$chown_user_name "$TARGET_DIRECTORY"
    # Clone the repository to a temporary directory
    wait_command git clone "$REPO_URL" "$TEMP_CLONE_DIRECTORY"

    # Move only the contents of the clone to the specified directory
    wait_command rsync -av "$TEMP_CLONE_DIRECTORY/" "$TARGET_DIRECTORY"

    # Remove the temporary clone directory
    wait_command rm -rf "$TEMP_CLONE_DIRECTORY"

    chown_user_name=$(whoami)
    sudo chown -R $chown_user_name:$chown_user_name "$TARGET_DIRECTORY"
    # Make folders writable
    wait_command sudo chmod -R 755 "$TARGET_DIRECTORY"
    wait_command sudo find "$TARGET_DIRECTORY" -type f -exec chmod 644 {} \;

    # Display the contents with line numbers
    config_file="$TARGET_DIRECTORY/classes/MySQLHandler.php"
    grep -vn "cat" "$config_file" >/dev/null 2>&1

    # Modify the values in lines for the config file
    line_num_username=41
    line_num_password=53
    line_num_database=64

    wait_command sudo sed -i "${line_num_username}s/.*/\tpublic static \$mMySQLDatabaseUsername = '$MYSQL_USER';/" "$config_file"
    wait_command sudo sed -i "${line_num_password}s/.*/\tpublic static \$mMySQLDatabasePassword = '$MYSQL_PASSWORD';/" "$config_file"
    wait_command sudo sed -i "${line_num_database}s/.*/\tpublic static \$mMySQLDatabaseName = '$MYSQL_DATABASE';/" "$config_file"

    # Enable the site in Apache
    wait_command sudo a2ensite $APACHE_SITE_CONF
    wait_command sudo a2dissite 000-default
    sudo systemctl reload apache2

    echo
    echo "Edit 'IP, DomainName, and DomainAlias' in the /etc/hosts file on the HOST computer. \
    Below line '127.0.1.1 your_hostname'  \
    add the following line: \
    your_server_IP www.mutillidae.com mutillidae.com \
    This will allow you to access the site by www.mutillidae.com in your local browser."

    log_message "Mutillidae.com installation and configuration completed successfully."
fi

if [ "$MYSQL_DATABASE" == "sqlilabs" ]; then
    TARGET_DIRECTORY="/var/www/sqlilabs.com"
    REPO_URL="https://github.com/Audi-1/sqli-labs.git"
    TEMP_CLONE_DIRECTORY="/tmp/$MYSQL_DATABASE-temp-clone"
    APACHE_SITE_CONF="$MYSQL_DATABASE.com.conf"
    CONF_PATH="/etc/apache2/sites-available/$APACHE_SITE_CONF"

    # Create the config content
    CONFIG_CONTENT=$(
        cat <<-EOL
# Create and save a config file for each of your sites
# filename format: "$APACHE_SITE_CONF" , Path: "$CONF_PATH"
# enable site command: a2ensite $APACHE_SITE_CONF

<Directory $TARGET_DIRECTORY>
    Require all granted
</Directory>
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $TARGET_DIRECTORY
    ServerName $MYSQL_DATABASE.com
    ServerAlias www.$MYSQL_DATABASE.com
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOL
    )

    # Create the config file
    echo "$CONFIG_CONTENT" | sudo tee "$CONF_PATH" # Use tee to write with sudo permissions
    mkdir -p $TARGET_DIRECTORY
    chown_user_name=$(whoami)
    sudo chown -R $chown_user_name:$chown_user_name "$TARGET_DIRECTORY"
    # Clone the repository to a temporary directory
    wait_command git clone "$REPO_URL" "$TEMP_CLONE_DIRECTORY"

    # Move only the contents of the clone to the specified directory
    wait_command rsync -av "$TEMP_CLONE_DIRECTORY/" "$TARGET_DIRECTORY"

    # Remove the temporary clone directory
    wait_command rm -rf "$TEMP_CLONE_DIRECTORY"
    wait_command sudo chmod -R 755 "$TARGET_DIRECTORY"
    wait_command sudo find "$TARGET_DIRECTORY" -type f -exec chmod 644 {} \;

    chown_user_name=$(whoami)
    sudo chown -R $chown_user_name:$chown_user_name "$TARGET_DIRECTORY"
    CONFIG_FILE="/var/www/sqlilabs.com/sql-connections/db-creds.inc"

    # Modify the values in lines for the config file
    sed -i -e "4s/\$dbuser ='root';/\$dbuser ='$MYSQL_USER';/" \
        -e "5s/\$dbpass ='';/$dbpass ='$MYSQL_PASSWORD';/" \
        -e "6s/\$dbname =\"security\";/$dbname =\"$MYSQL_DATABASE\";/" "$CONFIG_FILE"

    # Enable the site in Apache
    wait_command sudo a2ensite $APACHE_SITE_CONF
    wait_command sudo a2dissite 000-default
    sudo systemctl reload apache2

    echo
    echo "Edit 'IP, DomainName, and DomainAlias' in the /etc/hosts file on the HOST computer. \
    Below line '127.0.1.1 your_hostname'  \
    add the following line: \
    your_server_IP www.sqlilabs.com sqlilabs.com \
    This will allow you to access the site by www.sqlilabs.com in your local browser."

    log_message "sqlilabs.com installation and configuration completed successfully."
fi

# Continue with bWAPP installation and configuration if the chosen database is 'bwapp'
if [ "$MYSQL_DATABASE" == "bWAPP" ]; then
    TARGET_DIRECTORY="/var/www/bwapp.com"
    REPO_URL="https://github.com/lmoroz/bWAPP.git"
    TEMP_CLONE_DIRECTORY="/tmp/$MYSQL_DATABASE-temp-clone"
    APACHE_SITE_CONF="$MYSQL_DATABASE.com.conf"
    CONF_PATH="/etc/apache2/sites-available/$APACHE_SITE_CONF"

    # Create the config content
    CONFIG_CONTENT=$(
        cat <<-EOL
# Create and save a config file for each of your sites
# filename format: "$APACHE_SITE_CONF" , Path: "$CONF_PATH"
# enable site command: a2ensite $APACHE_SITE_CONF

<Directory $TARGET_DIRECTORY>
    Require all granted
</Directory>
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $TARGET_DIRECTORY
    ServerName $MYSQL_DATABASE.com
    ServerAlias www.$MYSQL_DATABASE.com
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOL
    )

    # Create the config file
    echo "$CONFIG_CONTENT" | sudo tee "$CONF_PATH" # Use tee to write with sudo permissions
    mkdir -p $TARGET_DIRECTORY
    chown_user_name=$(whoami)
    sudo chown -R $chown_user_name:$chown_user_name "$TARGET_DIRECTORY"
    # Clone the repository to a temporary directory
    wait_command git clone "$REPO_URL" "$TEMP_CLONE_DIRECTORY"

    # Move only the contents of the clone to the specified directory
    wait_command rsync -av "$TEMP_CLONE_DIRECTORY/" "$TARGET_DIRECTORY"
    wait_command rm -rf "$TEMP_CLONE_DIRECTORY"

    # Remove the temporary clone directory
    wait_command rm -rf "$TEMP_CLONE_DIRECTORY"

    wait_command cp -r /var/www/bwapp.com/bWAPP/* /var/www/bwapp.com
    wait_command rm -rf /var/www/bwapp.com/bWAPP

    #wait_command rm -rf "$TARGET_DIRECTORY/bWAPP"

    chown_user_name=$(whoami)
    sudo chown -R "$chown_user_name:$chown_user_name" "$TARGET_DIRECTORY"
    wait_command sudo chmod -R 755 "$TARGET_DIRECTORY"
 

    mkdir "$TARGET_DIRECTORY/logs"

    chmod 777 "$TARGET_DIRECTORY/passwords/"
    chmod 777 "$TARGET_DIRECTORY/images/"
    chmod 777 "$TARGET_DIRECTORY/documents"
    chmod 777 "$TARGET_DIRECTORY/logs"

    SETTINGS_FILE="$TARGET_DIRECTORY/admin/settings.php"
 
    wait_command sed -i "s|\$db_username = \"root\";|\$db_username = \"$MYSQL_USER\";|" "$SETTINGS_FILE"
    wait_command sed -i "s|\$db_password = \"\";|\$db_password = \"$MYSQL_PASSWORD\";|" "$SETTINGS_FILE"


    # Enable the site in Apache
    wait_command sudo a2ensite $APACHE_SITE_CONF
    wait_command sudo a2dissite 000-default
    sudo systemctl reload apache2

    echo
    echo "Edit 'IP, DomainName, and DomainAlias' in the /etc/hosts file on the HOST computer. \
    Below line '127.0.1.1 your_hostname'  \
    add the following line: \
    your_server_IP www.bwapp.com bwapp.com \
    This will allow you to access the site by www.bwapp.com in your local browser."

    log_message "bwapp.com installation and configuration completed successfully."

fi
