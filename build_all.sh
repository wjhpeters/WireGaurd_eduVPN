#!/bin/bash

#download wireguard repository
add-apt-repository ppa:wireguard/wireguard
apt-get update
apt-get install wireguard-dkms wireguard-tools linux-headers-$(uname -r)

#Create the private keys for the server
wg genkey | tee server_private_key | wg pubkey > server_public_key

#Create the config file of the wireguard interface
PrivateKey=`cat server_private_key`
cat <<EOF >/etc/wireguard/wg0.conf
[Interface]
Address = 10.200.200.1/24
SaveConfig = true
PrivateKey = $PrivateKey
ListenPort = 51820
EOF

#Create the network interface based on the wg0.conf file
wg-quick up wg0
systemctl enable wg-quick@wg0.service

#enable ip forwarding
sysctl -w net.ipv4.ip_forward=1

#set up the IP tables for wireguard
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p udp -m udp --dport 51820 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.200.200.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.200.200.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT

#get the current used network to make sure the vpn traffic gets routed to the correct network
networkName=`ip addr | awk '/state UP/ {print $2}' | head --bytes -1`
echo $networkName
iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o $networkName -j MASQUERADE

#install the web environment prerequisites 
apt install apache2
apt install qrencode
apt install php

#set up the correct firewall routes TODO: improve and check which ports need to be open
ufw enable

ufw allow 53
ufw allow out 53
ufw allow 80
ufw allow out 80
ufw allow 443
ufw allow out 443
ufw allow 51820/udp
ufw allow out 51820/udp

#set the route again otherwise this rule is overwriten TODO: check if there is a better way
iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o $networkName -j MASQUERADE

#set up the web environment for the PoC TODO: clean up PHP code
rm /var/www/html/index.html
cat <<EOF >/var/www/html/index.php
<html><head><title>eduVPN QR code PoC</title></head>
	<body>
		<a href="new.php">Create new QR code</a><br><hr>
		<?php $directories = glob("./" . '/*' , GLOB_ONLYDIR);
		foreach ($directories as &$dir) {
				?><a href="<?php echo $dir; ?>/tmp.png">QR code voor: <?php echo $dir; ?></a><br><br><?php
		} ?>
	</body>
</html>
EOF

cat <<EOF >/var/www/html/new.php
<?php 
$currentIP = $_SERVER['REMOTE_ADDR']; //Might not be the real adress need to fix before release
$currentIP = (string)$currentIP;

//Create folder for the current session | NOT safe need to create a unique hashed value to prevent overlap.
if (!file_exists($currentIP)) {
	shell_exec('mkdir '.$currentIP);
	//generate a private and public key for the connection
	shell_exec('wg genkey | tee '.$currentIP.'/'.$currentIP.'_private | wg pubkey > '.$currentIP.'/'.$currentIP.'_public');

	//Save the keys as variables
	$privateKey = shell_exec('cat '.$currentIP.'/'.$currentIP.'_private');
	$publicKey = shell_exec('cat '.$currentIP.'/'.$currentIP.'_public');
	
	$publicKey = trim(preg_replace('/\s+/', ' ', $publicKey));
	
	$directories = glob("./" . '/*' , GLOB_ONLYDIR);
	$ip_count = count($directories) + 1;
	
	//Create the content for the .conf file that WireGuard uses
$QR_code_content = '[Interface]
Address = 10.200.200.'.$ip_count.'/32
PrivateKey = '.$privateKey.'DNS = 1.1.1.1
ListenPort = 51820

[Peer]
PublicKey = fdGaBL17rnuib8bxGq6rMW4kCfG1eVIBHZ2gSaMbZWE=
Endpoint = 145.100.181.112:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21';
	
	//Create a .conf file for WireGuard so that it can correctly parse into a QR code
	$conf_file = $currentIP.'/tmp.conf';
	$handle = fopen($conf_file, 'w') or die('Cannot open file:  '.$conf_file);
	fwrite($handle, $QR_code_content);
	fclose($handle);
	
	shell_exec('sudo wg set wg0 peer '.$publicKey.' allowed-ips 10.200.200.'.$ip_count.'/32');

	//Create a QR code that people can use to connect to the server.
	shell_exec('qrencode -s 10 -d 300 -t png < '.$currentIP.'/tmp.conf -o '.$currentIP.'/tmp.png');
	
	//Redirect to the QR code
	header('Location: http://145.100.181.112/'.$currentIP.'/tmp.png');
} else {
	echo '<script type="text/javascript">alert("Your QR code already exists!");</script>';
	echo '<script type="text/javascript">window.location.replace("http://145.100.181.112");</script>';
}

?>
<html>
	<body>
		<h1>Hold on for one second while we create your safe connection!</h1>
	</body>
</html>
EOF