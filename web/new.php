<?php require "session.php";
 
$dev_name = $_POST['devName']; 
$exp_date = $_POST['expdate']; 
$exp_date = strtotime($exp_date);
$exp_date = date('Y-m-d', $exp_date);
$userID = $_SESSION["userID"];

try {
	$encryptedName = strtoupper(hash('sha256', $userID));
	shell_exec('mkdir '.$encryptedName);
	shell_exec('sudo wg genkey | tee '.$encryptedName.'/'.$encryptedName.'_private | wg pubkey > '.$encryptedName.'/'.$encryptedName.'_public');

	$privateKey = shell_exec('cat '.$encryptedName.'/'.$encryptedName.'_private');
	$publicKey = shell_exec('cat '.$encryptedName.'/'.$encryptedName.'_public');

	$privateKey = substr($privateKey, 0, -1);
	$publicKey = substr($publicKey, 0, -1);

	$stmt = $conn->prepare("SELECT COUNT(ID) FROM tunnels");
	$stmt->execute();
	$ip_count = $stmt->fetchColumn();
	$ip_count = $ip_count + 2;
	$stmt = $conn->prepare("SELECT public_ip FROM server WHERE ID = 1");
	$stmt->execute();
	$ipv4 = $stmt->fetchColumn();
	
	$stmt = $conn->prepare("SELECT public_key FROM server WHERE ID = 1");
	$stmt->execute();
	$serverPublicKey = $stmt->fetchColumn();
	
	$QR_code_content = '[Interface]
	Address = 10.200.200.'.$ip_count.'/32, fd42:42:42::'.$ip_count.'/128
	PrivateKey = '.$privateKey.'
	DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
	ListenPort = 51820

	[Peer]
	PublicKey = '.$serverPublicKey.'
	Endpoint = '.$ipv4.':51820
	AllowedIPs = 0.0.0.0/0, ::0
	PersistentKeepalive = 25';

	shell_exec('sudo wg set wg0 peer '.$publicKey.' allowed-ips 10.200.200.'.$ip_count.'/32,fd42:42:42::'.$ip_count.'/128');
	
	$stmt = $conn->prepare("INSERT INTO tunnels (user_id, device_name, access_token, experation_date) VALUES (".$userID.", '".$dev_name."', '".$QR_code_content."', '".$exp_date."')"); 
	$stmt->execute();
	
	shell_exec('rm -R '.$encryptedName);
	
	echo '<script type="text/javascript">';
	echo 'window.location = "account.php";';
	echo '</script>';
	
}
catch(PDOException $e) {
	echo $e;
	echo "Fail!";
}
$conn = null;
$stmt = null;
?>