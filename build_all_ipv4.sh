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
networkName=`ip addr | awk '/state UP/ {print $2}' | head --bytes -2`
echo $networkName
iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o $networkName -j MASQUERADE


#install the web environment prerequisites 
apt-get install -y apache2 -qq > /dev/null
apt-get install -y qrencode -qq > /dev/null
apt-get install -y php -qq > /dev/null
apt-get install -y php-mysql -qq > /dev/null

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
ipv4=`echo "${array[1]}"`

mkdir /var/www/html/QR

cat <<EOF >/var/www/html/QR/conn.php
<?php 
try {
$user = 'Testos';
$pass = 'Testos123!';
$dsn = 'mysql:host=localhost;dbname=wgenv';
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

cat <<EOF >/var/www/html/index.php
<?php require 'QR/conn.php';
try {
$userID = $_SERVER['MELLON_NAME_ID'];
$stmt = $conn->prepare("SELECT pseudo_id FROM users WHERE pseudo_id = '".$userID."'"); 
$stmt->execute();
$result = $stmt->fetchColumn();
if ($result == "") {
	$stmt = $conn->prepare("INSERT INTO users VALUES ('".$userID."')"); 
	$stmt->execute();
	echo '<script type="text/javascript">';
	echo 'console.log("New user");';
	echo '</script>';
} else {
	echo '<script type="text/javascript">';
	echo 'console.log("Known user");';
	echo '</script>';
}

$stmt = $conn->prepare("SELECT ID FROM users WHERE pseudo_id = '".$userID."'"); 
$stmt->execute();
$userID = $stmt->fetchColumn();
echo '<script type="text/javascript">';
echo 'console.log("UserId '.$userID.'");';
echo '</script>';
} catch(PDOException $e) {
	echo '<script type="text/javascript">';
	echo 'console.log("Connection failed: ' . $e->getMessage() . '");';
	echo '</script>';
}	?>
<html>
<head>
  <title>Dashboard</title>
	<style>
	form{width:100%;padding-left:30%;padding-right:30%;}
	input{margin:10px;}
	h1{width:100%;text-align:center;}
	div.device {width:25%;border:1px solid black;padding-left:20px;margin-bottom:20px;}
	div#sorter {width:100%;display:flex;flex-direction:row;flex-wrap:wrap;justify-content:space-evenly;}
	</style>
</head>
<body>
	<h1>Welkom bij het WireGuard eduVPN dashboard!</h1>
	<form action="new.php">
		<input type="text" name="devName" placeholder="Naam apparaat"/><br>
		<input type="text" name="devSpec" placeholder="Tweede naam"/><br>
		<input type="radio" name="type" value="notMobile" checked>Not mobile<br>
        <input type="radio" name="type" value="Mobile">Mobile<br>
		<input type="submit" value="add device"/>
	</form>
	<div id="sorter">
		<?php
		$sql = "SELECT deviceName, deviceSpecs, deviceType, config FROM devices WHERE user_id = ".$userID.";";
		foreach ($conn->query($sql) as $device) {
		?>
		<div class="device">
			<h2 class="customName"><?php echo $device['deviceName']; ?></h2>
			<h2 class="type"><?php echo $device['deviceSpecs']; ?></h2>
			<div class="link">
				<?php if ($device['deviceType'] == "mobile") {
				?><img src='<?php echo $device['config']; ?>'/><?php
				} else {
				?><h4 class="confFile"><?php echo $device['config']; ?></h4><?php
				}
				?>
			</div>
		</div><?php
		}
		?>
	</div>
</body>
</html>
EOF

cat <<EOF >/var/www/html/QR/new.php
<?php require "conn.php";

$deviceName = (!empty($_POST['devName']) ? $_POST['devName'] : '');
$deviceSpecs = (!empty($_POST['devSpec']) ? $_POST['devSpec'] : '');
$type = (!empty($_POST['type']) ? $_POST['type'] : '');

$mellonUserID = $_SERVER['MELLON_NAME_ID'];
$stmt = $conn->prepare("SELECT ID FROM users WHERE pseudo_id = '".$mellonUserID."'"); 
$stmt->execute();
$userID = $stmt->fetchColumn();

shell_exec('mkdir '.$mellonUserID);
shell_exec('sudo wg genkey | tee '.$mellonUserID.'/'.$mellonUserID.'_private | wg pubkey > '.$mellonUserID.'/'.$mellonUserID.'_public');

$privateKey = shell_exec('cat '.$mellonUserID.'/'.$mellonUserID.'_private');
$publicKey = shell_exec('cat '.$mellonUserID.'/'.$mellonUserID.'_public');

$privateKey = substr($privateKey, 0, -1);
$publicKey = substr($publicKey, 0, -1);



$stmt = $conn->prepare("SELECT COUNT(ID) FROM devices WHERE user_id = ".$userID.";");
$stmt->execute();
$ip_count = $stmt->fetchColumn();

$stmt = $conn->prepare("SELECT COUNT(ID) FROM users WHERE ID > ".$userID."");
$stmt->execute();
$ip_position = $stmt->fetchColumn();
$ip_position *= 5;

$ip_count = $ip_position + $ip_count;

$stmt = $conn->prepare("INSERT INTO users VALUES ('".$userID."')"); 
$stmt->execute();

$QR_code_content = '[Interface]
Address = 10.200.200.'.$ip_count.'/32
PrivateKey = '.$privateKey.'
DNS = 1.1.1.1
ListenPort = 51820

[Peer]
PublicKey = 15dMcxtL+ibbQJQoClOVyL0ewKPgWFId6QlPL8D0pUY=
Endpoint = 145.100.181.164:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25';

$conf_file = $mellonUserID.'/tmp.conf';
$handle = fopen($conf_file, 'w') or die('Cannot open file:  '.$conf_file);
fwrite($handle, $QR_code_content);
fclose($handle);

shell_exec('sudo wg set wg0 peer '.$publicKey.' allowed-ips 10.200.200.'.$ip_count.'/32');

?>
<html>
	<body>
		<h2><?php echo 'userID: '.$userID; ?></h2>
		<h2><?php echo 'Priv: '.$privateKey; ?></h2>
		<h2><?php echo 'Pub: '.$publicKey; ?></h2>
		<h2><?php echo 'IP count: ' . $ip_count; ?></h2>
		<?php if ($type == "mobile") {
			$QR_ascii = shell_exec('qrencode -t SVG -s 5 < '.$mellonUserID.'/tmp.conf');
		?>
		<p style="width:800px;height:800px;"><?php echo $QR_ascii; ?></p>
		<?php } else { ?>
		
		<?php }	?>
	</body>
</html>
<?php shell_exec('rm -R '.$mellonUserID); ?>

EOF

echo "########################################################################"
echo "# Webserver running on $ipv4"
echo "# 	Connect to generate QR code for a connection."
echo "#"
echo "# WireGuard server running on $ipv4:51820"
echo "# 	Connect to the server with this public key: $publicKey"
echo "########################################################################"