#!/bin/bash
sudo apt autoremove --purge apache2 mysql-server expect git wget curl php-db php-sqlite3 php php-xml php-common php-curl php-mysql php-xdebug libapache2-mod-php php-mbstring php-gd -y
&&
sudo rm -rf /etc/mysql /var/www /etc/apache2 /var/lib/apache2