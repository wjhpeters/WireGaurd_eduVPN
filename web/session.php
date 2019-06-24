<?php require "conn.php";
session_start(); 
$userID = $_SESSION["userID"];
try {
	
	$stmt = $conn->prepare("SELECT username FROM users WHERE ID = '".$userID."'"); 
	$stmt->execute();
	
	if($stmt->rowCount() > 0){
	}
	else {
		echo '<script type="text/javascript">';
		echo 'window.location = "index.php";'; 
		echo '</script>';
	}
}
catch(PDOException $e) {
		echo '<script type="text/javascript">';
		echo 'window.location = "index.php";'; 
		echo '</script>';
}
?>