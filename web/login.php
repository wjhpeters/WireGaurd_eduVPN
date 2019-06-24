<?php require "conn.php";

$username = (!empty($_POST['user_name']) ? $_POST['user_name'] : '');
$password = (!empty($_POST['user_pass']) ? $_POST['user_pass'] : '');
try {
	$stmt = $conn->prepare("SELECT user_pass FROM users WHERE username = '".$username."'");
	$stmt->execute();
	$hash = $stmt->fetchColumn();
	$password = strtoupper(hash('sha256', $password));
	if($password == $hash) {
		$stmt = $conn->prepare("SELECT ID FROM users WHERE username = '".$username."'");
		$stmt->execute();
		$userID = $stmt->fetchColumn();
		$_SESSION["userID"] = $userID;		
		echo '<script type="text/javascript">';
		echo 'window.location = "account.php";';
		echo '</script>';
	} else {
		echo '<script type="text/javascript">';
		echo 'alert("Wrong Password!");';
		echo 'window.location = "index.php";';
		echo '</script>';
	}
}
catch(PDOException $e) {
		echo '<script type="text/javascript">';
		echo 'alert("Wrong username!");';
		echo 'window.location = "index.php";';
		echo '</script>';
}
$conn = null;
$stmt = null;
?>
