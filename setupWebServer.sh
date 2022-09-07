#!/bin/bash
#Amended original by me to support / customixe for MSFT SQL Server
#A LOT of Google-Fu involved here!
#hardev@nutanix.com Aug'22
set -ex

sudo amazon-linux-extras enable php7.4
sudo yum clean metadata
sudo yum install -y php-cli php-pdo php-fpm php-json php-mysqlnd
sudo amazon-linux-extras install -y nginx1
sudo yum install -y gcc gcc-c++ git unzip yum-utils
sudo yum install -y php-{devel,dom,pear,mbstring,gd,bcmath,intl}
sudo su - -c "curl https://packages.microsoft.com/config/rhel/7/prod.repo > /etc/yum.repos.d/mssql-release.repo"
sudo yum remove -y unixODBC-utf16 unixODBC-utf16-devel
sudo ACCEPT_EULA=Y yum install -y mssql-tools msodbcsql17 unixODBC-devel --disablerepo=amzn*
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bash_profile
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
sudo cp -f "/etc/php.ini" "/tmp/php.ini.bk"
sudo pecl7 install sqlsrv pdo_sqlsrv || sudo pecl install sqlsrv pdo_sqlsrv
sudo cp -f "/tmp/php.ini.bk" "/etc/php.ini"
sqlvar=$(php -r "echo ini_get('extension_dir');")
sudo chmod 0755 $sqlvar/sqlsrv.so && sudo chmod 0755 $sqlvar/pdo_sqlsrv.so
sudo su - -c "echo extension=pdo_sqlsrv.so >> `php --ini | grep \"Scan for additional .ini files\" | sed -e \"s|.*:\s*||\"`/30-pdo_sqlsrv.ini"
sudo su - -c "echo extension=sqlsrv.so >> `php --ini | grep \"Scan for additional .ini files\" | sed -e \"s|.*:\s*||\"`/20-sqlsrv.ini"
#exit
sudo amazon-linux-extras install epel -y
sudo rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm
sudo setenforce 0 || true
sudo sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
sudo systemctl stop firewalld || true
sudo systemctl disable firewalld || true
sudo mkdir -p /var/www/laravel
echo "server {
 listen 80 default_server;
 listen [::]:80 default_server ipv6only=on;
root /var/www/laravel/public/;
 index index.php index.html index.htm;
location / {
 try_files \$uri \$uri/ /index.php?\$query_string;
 }
 # pass the PHP scripts to FastCGI server listening on /var/run/php[74]-fpm.sock
 location ~ \.php$ {
 try_files \$uri /index.php =404;
 fastcgi_split_path_info ^(.+\.php)(/.+)\$;
 fastcgi_pass 127.0.0.1:9000;
 fastcgi_index index.php;
 fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
 include fastcgi_params;
 }
}" | sudo tee /etc/nginx/conf.d/laravel.conf
sudo sed -i 's/80 default_server/80/g' /etc/nginx/nginx.conf
if `grep "cgi.fix_pathinfo" /etc/php.ini` ; then
 sudo sed -i 's/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php.ini
else
 sudo sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php.ini
fi
sudo systemctl enable php-fpm
sudo systemctl enable nginx
sudo systemctl restart php-fpm
if [ ! -e /usr/local/bin/composer ]
then
 curl -sS https://getcomposer.org/installer | php
 sudo mv composer.phar /usr/local/bin/composer
 sudo chmod +x /usr/local/bin/composer
fi
#Laravel Tasks Application is at the next git repoo - supports a database called homestead 
#on MySQL, so need to fix the config files and attributes to support MSFT SQL Server.
#I got my sed on dude!
sudo git clone https://github.com/ideadevice/quickstart-basic.git /var/www/laravel
sudo sed -i 's/DB_HOST=.*/DB_HOST=127.0.0.1/' /var/www/laravel/.env
sudo sed -i "s/DB_DATABASE=.*/DB_DATABASE=$1/" /var/www/laravel/.env
sudo sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$2/" /var/www/laravel/.env
sudo sed -i "s/DB_USERNAME=.*/DB_USERNAME=$3/" /var/www/laravel/.env
sudo su - -c "echo \"DB_CONNECTION=sqlsrv\" >> /var/www/laravel/.env"
sudo su - -c "echo \"DB_PORT=8888\" >> /var/www/laravel/.env"
sudo su - -c "cd /var/www/laravel; composer --no-interaction install"
sudo sed -i 's/localhost/127\.0\.0\.1/' /var/www/laravel/config/database.php
sudo sed -i "s/forge/$1/" /var/www/laravel/config/database.php
sudo sed -i '0,/mysql/s//sqlsrv/' /var/www/laravel/config/database.php
sudo sed -i  "s/'driver'   => 'sqlsrv',/'driver'   => 'sqlsrv','port' => env('DB_PORT', '8888'),/" /var/www/laravel/config/database.php
sudo sed  -i "s/'DB_USERNAME', 'homestead'/'DB_USERNAME', '$3'/" /var/www/laravel/config/database.php
sudo sed  -i "s/'DB_PASSWORD', ''/'DB_PASSWORD', '$2'/" /var/www/laravel/config/database.php
sudo sed  -i 's/listen = \/run\/php-fpm\/www.sock/listen = 127.0.0.1:9000/' /etc/php-fpm.d/www.conf
sudo systemctl restart nginx
sudo systemctl restart php-fpm

#Wait for the ssh tunnekl back to the database server
tunupandrunning="DOWN"
while [[ $tunupandrunning == "DOWN" ]]
 do
   echo "==Tunnel is DOWN"
   sleep 10
   (netstat -tunl | grep '127.0.0.1:8888') && tunupandrunning="UP"
 done
 echo "====Tunnel is UP"
 
#Migrate database only of this is the first webserver
if [ $4 == "0" ]; then
 sudo su - -c "cd /var/www/laravel; php artisan migrate"
fi
sudo chown -R nginx:nginx /var/www/laravel
sudo chmod -R 777 /var/www/laravel/
sudo systemctl restart nginx
echo "===== Done"
exit;exit