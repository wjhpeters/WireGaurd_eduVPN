#!/bin/bash
#download wireguard repository and install it
add-apt-repository -y ppa:wireguard/wireguard > /dev/null 2>&1
apt-get update -qq > /dev/null
apt-get install -y wireguard -qq > /dev/null
#Create the private keys for the server
wg genkey | tee server_private_key | wg pubkey > server_public_key
#Create the config file of the wireguard interface
PrivateKey=`cat server_private_key`
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
ipadresses=`hostname -i`
IFS=' ' read -r -a array <<< "$ipadresses"
ipv6=`echo "${array[0]}"`
ipv4=`echo "${array[2]}"`

cat <<EOF >/var/www/html/index.php
<html><head><title>eduVPN QR code PoC</title></head>
	<body>
		<a href="new.php">Create new QR code</a><br><hr>
		<?php \$directories = glob("./" . '/*' , GLOB_ONLYDIR);
		foreach (\$directories as \$dir) {
				?><a href="<?php echo \$dir; ?>/tmp.png">QR code voor: <?php echo \$dir; ?></a><br><br><?php
		} ?>
	</body>
</html>
EOF

publicKey=`cat server_public_key`

cat <<EOF >/var/www/html/new.php
<?php 
\$currentIP = \$_SERVER['REMOTE_ADDR']; //Might not be the real adress need to fix before release
\$currentIP = (string)\$currentIP;

//Create folder for the current session | NOT safe need to create a unique hashed value to prevent overlap.
if (!file_exists(\$currentIP)) {
	mkdir(\$currentIP, 0777);
	//generate a private and public key for the connection
	shell_exec('wg genkey | tee '.\$currentIP.'/'.\$currentIP.'_private | wg pubkey > '.\$currentIP.'/'.\$currentIP.'_public');

	//Save the keys as variables
	\$privateKey = shell_exec('cat '.\$currentIP.'/'.\$currentIP.'_private');
	\$publicKey = shell_exec('cat '.\$currentIP.'/'.\$currentIP.'_public');
	
	\$publicKey = trim(preg_replace('/\s+/', ' ', \$publicKey));
	
	\$directories = glob("./" . '/*' , GLOB_ONLYDIR);
	\$ip_count = count(\$directories) + 1;
	
	//Create the content for the .conf file that WireGuard uses
\$QR_code_content = '[Interface]
Address = 10.200.200.'.\$ip_count.'/32, fd42:42:42::'.\$ip_count.'/128
PrivateKey = '.\$privateKey.'DNS = 1.1.1.1
ListenPort = 51820

[Peer]
PublicKey = $publicKey
Endpoint = $ipv6:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25';
	
	//Create a .conf file for WireGuard so that it can correctly parse into a QR code
	\$conf_file = \$currentIP.'/tmp.conf';
	\$handle = fopen(\$conf_file, 'w') or die('Cannot open file:  '.\$conf_file);
	fwrite(\$handle, \$QR_code_content);
	fclose(\$handle);
	
	shell_exec('sudo wg set wg0 peer '.\$publicKey.' allowed-ips 10.200.200.'.\$ip_count.'/32,fd42:42:42::'.\$ip_count.'/128');

	//Create a QR code that people can use to connect to the server.
	shell_exec('qrencode -s 10 -d 300 -t png < '.\$currentIP.'/tmp.conf -o '.\$currentIP.'/tmp.png');
	
	//Redirect to the QR code
	header('Location: '.\$currentIP.'/tmp.png');
} else {
	echo '<script type="text/javascript">alert("Your QR code already exists!");</script>';
	echo '<script type="text/javascript">window.location.replace($ipv4);</script>';
}

?>
<html>
	<body>
		<h1>Hold on for one second while we create your safe connection!</h1>
	</body>
</html>
EOF

echo "########################################################################"
echo "# Webserver running on $ipv4"
echo "# 	Connect to generate QR code for a connection."
echo "#"
echo "# WireGuard server running on $ipv4 :51820 or $ipv6 :51820"
echo "# 	Connect to the server with this public key: $publicKey"
echo "########################################################################"