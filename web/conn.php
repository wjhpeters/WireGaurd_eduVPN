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