<?php require "session.php"; 
$today = date("Y-m-d");
$expDate = date("Y-m-d", strtotime('+2 months'));
$userID = $_SESSION["userID"];
$encryptedName = strtoupper(hash('sha256', $userID));
shell_exec('mkdir '.$encryptedName);
?>
<html>
<head>
  <title>Dashboard</title>
	<style>
	form{width:100%;padding-left:30%;padding-right:30%;}
	input{margin:10px;}
	h1{width:100%;text-align:center;}
	div.device {width:50%;border:1px solid black;padding-left:20px;margin-bottom:20px;}
	div#sorter {width:100%;display:flex;flex-direction:row;flex-wrap:wrap;justify-content:space-evenly;}
	</style>
</head>
<body>
	<h1>Welkom bij het WireGuard eduVPN dashboard!</h1>
	<form action="new.php" method="POST">
		<input type="text" name="devName" placeholder="Naam apparaat"/><br>
		<input type="date" name="expdate" value="<?php echo $today; ?>" min="<?php echo $today; ?>" max="<?php echo $expDate; ?>"><br>
		<input type="submit" value="add tunnel"/>
	</form>
	<div id="sorter">
		<?php
		$sql = "SELECT device_name, access_token, experation_date FROM tunnels WHERE user_id = ".$userID.";";
		foreach ($conn->query($sql) as $device) {
			$conf_file = $encryptedName.'/tmp.conf';
			$handle = fopen($conf_file, 'w') or die('Cannot open file:  '.$conf_file);
			fwrite($handle, $device['access_token']);
			fclose($handle);
			$QR_ascii = shell_exec('qrencode -t SVG -s 5 < '.$encryptedName.'/tmp.conf');
		?>
		<div class="device">
			<h2 class="customName"><?php echo $device['device_name']; ?></h2>
			<div class="link">
				<h4 class="confFile"><?php echo $device['access_token']; ?></h4>
				<br><hr><br>
				<p style="width:800px;height:800px;"><?php echo $QR_ascii; ?></p>
			</div>
		</div><?php
		}
		?>
	</div>
</body>
</html>
<?php shell_exec('rm -R '.$encryptedName); ?>