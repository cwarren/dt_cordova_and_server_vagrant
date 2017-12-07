#! /usr/bin/env bash

# Variables
APPENV=local
DBHOST=localhost
DBPASSWD=rootformysqlvagrantprovisioning

echo -e "\n--- Set up the environment vars ---\n"
cat > /etc/profile.d/java_android_gradle.sh << EOF
export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
export ANDROID_HOME="/opt/android-sdk-linux"
export GRADLE_HOME="/opt/gradle"
export PATH="\${PATH}:\${ANDROID_HOME}/platform-tools:\${ANDROID_HOME}/tools:\${ANDROID_HOME}/build-tools/25.0.2:\${GRADLE_HOME}/gradle-4.3.1/bin"
EOF
source /etc/profile.d/java_android_gradle.sh

echo -e "\n--- Add some repos to update our distro ---\n"
add-apt-repository -y ppa:ondrej/php

echo -e "\n--- Updating packages list ---\n"
apt-get update

echo -e "\n--- Install base packages ---\n"
apt-get -y install emacs
apt-get -y install curl
apt-get -y install zip 
apt-get -y install unzip 
apt-get -y install apache2
apt-get -y install libwww-perl

echo -e "\n--- Install and configure git ---\n"
apt-get -y install git
cat >> ~vagrant/.gitconfig <<EOF
[core]
        fileMode = false
        logallrefupdates = true
        symlinks = true
        ignorecase = false
        autocrlf = false
EOF

echo -e "\n--- Install cordova packages ---\n"
apt-get -y install nodejs npm
ln -s /usr/bin/nodejs /usr/bin/node
npm install -g cordova


echo -e "\n--- Install packages and tools to support cordova: JDK, android sdk, and gradle ---\n"
apt-get -y install default-jdk
mkdir -p /root/.android
touch  /root/.android/repositories.cfg
mkdir -p /home/vagrant/.android

mkdir -p $ANDROID_HOME
cd $ANDROID_HOME
wget https://dl.google.com/android/repository/tools_r25.2.3-linux.zip
unzip tools_r25.2.3-linux.zip
# NOTE: ideally the below commands would do the SDK install/update, but it doesn't work because
# the sdk update has a license acceptance step which the yes command doesn't seem to satisfy
# cd tools
# yes | ./android update sdk --no-ui
chown -R vagrant /home/vagrant/.android
chgrp -R vagrant /home/vagrant/.android


mkdir -p $GRADLE_HOME
cd $GRADLE_HOME
wget https://services.gradle.org/distributions/gradle-4.3.1-bin.zip
unzip -d /opt/gradle gradle-4.3.1-bin.zip

# wget http://dl.google.com/android/android-sdk_r24.2-linux.tgz
# tar -xvf android-sdk_r24.2-linux.tgz
# cd android-sdk-linux/tools
# # install all sdk packages
# ./android update sdk --no-ui

# apt-get -y install android-studio

echo -e "\n--- Installing vue-cli packages (via npm) ---\n"
npm install -g vue-cli

echo -e "\n--- Installing PHP-specific packages ---\n"
apt-get -y install php 
apt-get -y install php-zip
apt-get -y install php-mysql
apt-get -y install libapache2-mod-php
apt-get -y install php-curl
apt-get -y install php-gd
apt-get -y install php-mcrypt
apt-get -y install php-apcu

echo -e "\n--- Install MySQL specific packages and settings ---\n"
echo "mysql-server mysql-server/root_password password $DBPASSWD" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $DBPASSWD" | debconf-set-selections
apt-get -y install mysql-server

echo -e "\n--- Install phpmyadmin specific packages and settings ---\n"
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $DBPASSWD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $DBPASSWD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $DBPASSWD" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
apt-get -y install phpmyadmin

echo -e "\n--- Setting document root to public directory ---\n"
if ! [ -L /var/www ]; then
    rm -rf /var/www
    ln -fs /vagrant_shared /var/www
    ln -s /usr/share/phpmyadmin/ /var/www/phpmyadmin

    # put a couple of test files in place
    echo "<html><head><title>hello world</title></head><body><h2>hello world</h2>things are working, at least up to this point</body></html>" > /vagrant_shared/hello_world.html
    echo "<html><head><title>hello php</title></head><body><h2>hello php</h2>if working, should see something here: <?php echo 'hello php';?></body></html>" > /vagrant_shared/hello_php.php
fi

echo -e "\n--- Enabling mod-rewrite ---\n"
a2enmod rewrite

echo -e "\n--- Allowing Apache override to all ---\n"
sed -i "s/AllowOverride None/AllowOverride All/g" /etc/apache2/apache2.conf

echo -e "\n--- turn off apache sendfile (which is bugged under virtual box, leading to weird caching issues) ---\n"
cat >> /etc/apache2/apache2.conf <<EOF
EnableSendfile off
EOF

echo -e "\n--- See the PHP errors ---\n"
sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.1/apache2/php.ini
sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.1/apache2/php.ini

# NOTE: this Listen directive addition can cause problems if trying to re-provision an existing machine - manually edit the /etc/apache2/ports.conf file to remove dupes, then service apache2 restart
echo -e "\n--- Configure Apache to use phpmyadmin ---\n"
echo -e "\n\n#VAGRANT ADDED - for phpmyadmin\nListen 81\n" >> /etc/apache2/ports.conf

cat >> /etc/apache2/conf-available/phpmyadmin.conf <<EOF

# VAGRANT: for phpmyadmin
<VirtualHost *:81>
    ServerAdmin webmaster@localhost
    DocumentRoot /usr/share/phpmyadmin
    DirectoryIndex index.php
    ErrorLog ${APACHE_LOG_DIR}/phpmyadmin-error.log
    CustomLog ${APACHE_LOG_DIR}/phpmyadmin-access.log combined
</VirtualHost>
EOF
a2enconf phpmyadmin

echo -e "\n--- Set up apache environment variables ---\n"
cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
# VAGRANT
<VirtualHost *:80>
    DocumentRoot /var/www
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    SetEnv APP_ENV $APPENV
    SetEnv DB_HOST $DBHOST
    SetEnv DB_PASS $DBPASSWD
</VirtualHost>
EOF

echo -e "\n--- Restarting Apache ---\n"
service apache2 restart

echo -e "\n\n\nNOTE: automated securing of mysql not working; be"
echo "sure to run"
echo "    \$ mysql_secure_installation"
echo "manually!"
echo
echo "android SDK must me handled manually because the license acceptance"
echo "doesn't seem to be able to be done programatically"
echo "    $ cd \$ANDROID_HOME/tools"
echo "    $ sudo ./android update sdk --no-ui"
echo
echo "also, don't forget to configure git:"
echo "    $ git config --global user.name \"yourusername\""
echo "    $ git config --global user.email=youremail@provider.com"
echo "and maybe also"
echo "    $ git config --global core.safecrlf false"
echo "to avoid a bunch of warning messages that are usually irrelevant"