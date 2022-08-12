<?php

session_start();
include_once 'includes/config.php';
include('includes/cart.php');

if (isset($_SESSION['currentStore'])) {
    $store = unserialize($_SESSION['currentStore']);
} else {
    $store = new Cart();
}

if (isset($_POST['selecteditem']) && isset($_POST['selectquantity'])) {

    foreach ($_POST['selectquantity'] as $pro_id => $pro_qyt) {

        if ($pro_qyt != '' && $pro_qyt > 0 && $pro_id != '') {
            $store->addToCartByQty($pro_id, (int) $pro_qyt);
        }
    }
}

if (isset($_POST['confirmOrder'])) {
    

    $_POST['firstname'] = $_SESSION['firstname'] ;
    $_POST['lastname'] = $_SESSION['lastname'];
    $_POST['email'] = $_SESSION['email'];
    $_POST['telephone'] = $_SESSION['telephone'];
    $_POST['fax']  = $_SESSION['fax'] ;
    $_POST['confirm'] = $_SESSION['confirm'];
    $_POST['password'] = $_SESSION['password'];
    $_POST['company'] = $_SESSION['company'];
    $_POST['address_1'] = $_SESSION['address_1'];
    $_POST['address_2'] = $_SESSION['address_2']; 
    $_POST['city'] = $_SESSION['city']; 
    $_POST['postcode'] = $_SESSION['postcode'];
    $ErroMsg = array();
    if (strlen($_POST['firstname']) < 2 || strlen($_POST['firstname']) > 50) {
        $ErroMsg[] = 'Customer firstname can not be less than 1 and more than 50';
    }
    if (strlen($_POST['lastname']) < 2 || strlen($_POST['lastname']) > 50) {
        $ErroMsg[] = 'Lastname can not be less than 1 and more than 50';
    }
    if (strlen($_POST['email']) < 2 || strlen($_POST['email']) > 50) {
        $ErroMsg[] = 'Email can not be less than 1 and more than 50';
    }
    if (strlen($_POST['telephone']) < 10 || !is_numeric($_POST['telephone'])) {
       $ErroMsg[] = 'Telephone should be numeric and not less than 10 characters long';
    }
    if (strlen($_POST['fax']) < 2 || !is_numeric($_POST['fax']) > 50) {
        $ErroMsg[] = 'fax should be numeric and not less than 10 characters long';
    }
    if (strlen($_POST['password']) < 2 || strlen($_POST['password']) > 50) {
       $ErroMsg[] = 'password can not be less than 1 and more than 50';
    }
    if (strlen($_POST['confirm']) < 2 || strlen($_POST['confirm']) > 50) {
        $ErroMsg[] = 'password can not be less than 1 and more than 50';
    }
    if ($_POST['password'] != $_POST['confirm']) {
        $ErroMsg[] = 'password and confirmation do not match....';
    }
    if (strlen($_POST['company']) < 2 || strlen($_POST['company']) > 50) {
       $ErroMsg[] = 'Company can not be less than 1 and more than 50';
    }
    if (strlen($_POST['address_1']) < 2 || strlen($_POST['address_1']) > 50) {
        $ErroMsg[] = 'Address can not be less than 1 and more than 50';
    }
    if (strlen($_POST['address_2']) < 2 || strlen($_POST['address_2']) > 50) {
       $ErroMsg[] = 'Address can not be less than 1 and more than 50';
    }
    if (strlen($_POST['city']) < 2 || strlen($_POST['city']) > 50) {
        $ErroMsg[] = 'city can not be less than 1 and more than 50';
    }
    if (strlen($_POST['postcode']) < 2 || !is_numeric($_POST['postcode']) > 50) {
       $ErroMsg[] = 'Post-code cannot be less than 1 and non-numeric';
    }
    $ErroMsg = array(); //for demo 
    if (!empty($ErroMsg)) {
        //include_once 'includes/config.php';
        $_SESSION['ErroMsg'] = $ErroMsg;
        $extra = 'checkout.php?message=1';
        header("Location:$extra");
    } else {
   /* pass information to the database.. */
    $invnum = $store->addCustInformation($_POST['firstname'],$_POST['lastname'],$_POST['email'],$_POST['telephone'],
                                     $_POST['fax'],$_POST['password'],$_POST['company'],$_POST['address_1'],$_POST['address_2'],$_POST['city'],$_POST['postcode']);
    $store->emptycart();
    unset($_SESSION['currentStore']);
    unset($_SESSION['firstname']) ;
    unset($_SESSION['lastname']);
    unset($_SESSION['email']);
    unset($_SESSION['telephone']);
    unset($_SESSION['fax'] );
    unset($_SESSION['confirm']);
    unset($_SESSION['password']);
    unset($_SESSION['company']);
    unset($_SESSION['address_1']);
    unset($_SESSION['address_2']); 
    unset($_SESSION['city']); 
    unset($_SESSION['postcode']);
    
    $extra = 'checkout.php?dataposted=1&invoicenum='.$invnum ;
    header("Location:$extra");

    }
}

$_SESSION['currentStore'] = serialize($store);

if(!isset($_POST['confirmOrder']) && !isset($_SESSION['ErroMsg'])){
$extra = 'showcart.php';
header("Location:$extra");
}
if(isset($_SESSION['ErroMsg'])){
      $extra = 'products.php?message=1';
      header("Location:$extra");
}
unset($_POST['confirmOrder']);
?>
