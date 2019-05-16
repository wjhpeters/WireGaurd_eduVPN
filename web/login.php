<?php require "conn.php";

$username = $_GET['user']; 
$password = $_GET['pass']; 
try {
	$stmt = $conn->prepare("SELECT user_pass FROM users WHERE username = '" . $username . "'"); 
	$stmt->execute();
	$hash = $stmt->fetchColumn();
	$password = strtoupper(hash('sha256', $password));
	if($password == $hash) { 
	echo "Succes!";
	} else {
	echo "Fail!";
	}
}
catch(PDOException $e) {
	echo "Fail!";
}
$conn = null;
$stmt = null;
?>
