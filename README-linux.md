gsb-build-local
===============

### Build Notes: Linux

#### Install PHP 5.6 (apache2 will be installed as well) 
```bash 
sudo add-apt-repository ppa:ondrej/php
sudo apt-get update
sudo apt-get install php5.6 php5.6-mbstring php5.6-mcrypt php5.6-mysql php5.6-xml mysql-server mysql-client unzip git php5.6-xml php5.6-curl php5.6-gd php-memcached memcached php5.6-zip
```

#### Set PHP5.6 as default
```bash
sudo a2dismod php7.0 ; sudo a2enmod php5.6 ; sudo service apache2 restart
sudo update-alternatives --set php /usr/bin/php5.6
```

#### Get this build script locally
```bash
mkdir /home/user/git
git clone https://github.com/gsbitse/gsb-build-local.git
cp ~/git/gsb-build-local/global.cfg.example global.cfg
```

#### Make required folders 
```bash
sudo mkdir /var/www/tmp
sudo chmod 777 /var/www/tmp
sudo chmod 777 /var/www/html
sudo mkdir /var/www/html/gsb_public
sudo chmod 777 /var/www/html/gsb_public
```

#### Apache Configuration 
```bash
sudo a2enmod rewrite 
```

```bash
add to apache config
  set paths to /var/www/html/gsb_public
  <Directory />
     Options FollowSymlinks
     AllowOverride All
  </Directory>
```

#### Install Composer
```bash
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
```

```bash
In .bashrc file: 
export PATH="$HOME/.config/composer/vendor/bin:$PATH"
```

```bash
composer global require drush/drush:8.*
```

#### Git config settings - whitespace fix
```bash
~/.gitconfig

[apply]
	whitespace = fix
```

#### Change php memory limit configuration
```bash
sudo nano /etc/php/5.6/apache2/php.ini
	- memory limit
```

#### Create local build database 
```bash
create database gsb_public;
grant all privileges on gsb_public.* to 'root'@'localhost' identified by 'password';
```

#### Add user group to apache for file writing
```bash
sudo usermod -a -G username www-data
```