<?php require 'check_ses.php'; ?>
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
	<form action="new.php" method="POST">
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