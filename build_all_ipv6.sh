#!/bin/bash
#download wireguard repository and install it
add-apt-repository -y ppa:wireguard/wireguard > /dev/null 2>&1
apt-get update -qq > /dev/null
apt-get install -y wireguard -qq > /dev/null
#Create the private keys for the server
wg genkey | tee server_private_key | wg pubkey > server_public_key
#Create the config file of the wireguard interface
PrivateKey=`cat server_private_key`
PublicKey=`cat server_public_key`

cat <<EOF >/etc/wireguard/wg0.conf
[Interface]
Address = 10.200.200.1/24, fd42:42:42::1/64
SaveConfig = true
PrivateKey = $PrivateKey
ListenPort = 51820
EOF

#Create the network interface based on the wg0.conf file
wg-quick up wg0
systemctl enable wg-quick@wg0.service

#enable ip forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

networkName=`ip addr | awk '/state UP/ {print $2}' | head --bytes -2`
echo $networkName

#set up the IP tables for wireguard
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p udp -m udp --dport 51820 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.200.200.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -s fd42:42:42::0/64 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.200.200.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -s fd42:42:42::0/64 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i wg0 -o $networkName -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A FORWARD -i wg0 -o $networkName -m conntrack --ctstate NEW -j ACCEPT

#get the current used network to make sure the vpn traffic gets routed to the correct network

iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o $networkName -j MASQUERADE
ip6tables -t nat -A POSTROUTING -s fd42:42:42::0/64 -o $networkName -j MASQUERADE


#install the web environment prerequisites 
apt-get install -y apache2 -qq > /dev/null
apt-get install -y qrencode -qq > /dev/null
apt-get install -y php -qq > /dev/null
apt-get install -y php-mysql -qq > /dev/null
apt-get install -y mysql-server -qq > /dev/null

echo "Please enter your prefered username for MySQL:"
read username
echo "Please enter your prefered password for MySQL:"
read password

ipadresses=`hostname -i`
IFS=' ' read -r -a array <<< "$ipadresses"
ipv6=`echo "${array[0]}"`
ipv4=`echo "${array[2]}"`

mysql -uroot -p "CREATE USER ${username}@localhost IDENTIFIED BY '${password}';"
mysql -uroot -p "grant all privileges on *.* to ${username}@localhost;"

mysql -u$username -p$password <<MY_QUERY
CREATE DATABASE WireGuardDB;
USE WireGuardDB;
CREATE TABLE IF NOT EXISTS server (ID INT AUTO_INCREMENT PRIMARY KEY, public_key VARCHAR(200) NOT NULL, private_key VARCHAR(200) NOT NULL, public_ip VARCHAR(50) NOT NULL);
CREATE TABLE IF NOT EXISTS users (ID INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(200) UNIQUE NOT NULL, user_pass VARCHAR(64) NOT NULL);
CREATE TABLE IF NOT EXISTS tunnels (ID INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, device_name VARCHAR(200) NOT NULL, access_token VARCHAR(512) NOT NULL, experation_date DATE NOT NULL);
CREATE TABLE IF NOT EXISTS logs (ID INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, log_type INT NOT NULL, log_content BLOB NOT NULL, experation_date DATE NOT NULL, saved BIT NOT NULL);
ALTER TABLE tunnels ADD CONSTRAINT fk_user_tunnels FOREIGN KEY(user_id) REFERENCES users(ID) ON DELETE CASCADE;
ALTER TABLE logs ADD CONSTRAINT fk_user_logs FOREIGN KEY(user_id) REFERENCES users(ID) ON DELETE CASCADE;
INSERT INTO server (public_key, private_key, public_ip) VALUES ("$PublicKey", "$PrivateKey", "$ipv4");

MY_QUERY

#set up the correct firewall routes TODO: improve and check which ports need to be open
echo "y" | ufw enable

ufw allow 22
ufw allow 53
ufw allow out 53
ufw allow 80
ufw allow out 80
ufw allow 443
ufw allow out 443
ufw allow 51820/udp
ufw allow out 51820/udp

ufw reload

#set the route again otherwise this rule is overwriten TODO: check if there is a better way
iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o $networkName -j MASQUERADE
ip6tables -t nat -A POSTROUTING -s fd42:42:42::0/64 -o $networkName -j MASQUERADE

#add certain commands for the www-data to manage the WireGuard interface
echo 'www-data  ALL=(ALL) NOPASSWD: /usr/bin/wg' >> /etc/sudoers


#set up the web environment for the PoC TODO: clean up PHP code
rm /var/www/html/index.html
#make sure the webserver can add folders
chown -R www-data:www-data /var/www/html
#get the ip adresses that are required for the interface setup

cat <<EOF >/var/www/html/conn.php
<?php 
try {
$user = '$username';
$pass = '$password';
$dsn = 'mysql:host=localhost;dbname=WireGuardDB';
$options = array(
	PDO::MYSQL_ATTR_INIT_COMMAND => 'SET NAMES utf8',
); 
$conn = new PDO($dsn, $user, $pass, $options);
$conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e){
 // report error message
 echo $e->getMessage();
}
?>
EOF

mv web/index.php /var/www/html/index.php
mv web/login.php /var/www/html/login.php
mv web/new.php /var/www/html/new.php
mv web/account.php /var/www/html/account.php
mv web/session.php /var/www/html/session.php

echo "########################################################################"
echo "# Webserver running on $ipv4"
echo "# 	Connect to generate QR code for a connection."
echo "########################################################################"