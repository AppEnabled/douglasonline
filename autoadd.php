<?php
session_start();
include_once 'includes/config.php';
include('includes/cart.php');
header("Content-type: text/json");

$Item = "";

if (isset($_SESSION['currentStore'])){
    $store = unserialize($_SESSION['currentStore']);
}else {
    $store = new Cart();
}

if(isset($_POST['quantity'])&& !isset($_POST['product_id']) && !isset($_POST['selecteditem'])){
    
foreach($_POST['quantity'] as $pro_id=>$pro_qyt){
    
    $store->addToCartByQty($pro_id,(int)$pro_qyt);
   
}

}else{
    
    $json = array();
    $Item  = $_POST['product_id'];
    $store->getProduct($Item);
    $store->addToCart($Item);
    $totalnumberOfItems = 0;
    $valueOfItemsOnCart = 0;
    
     foreach ($store->ShoppingCart as $product => $info) {
        $totalnumberOfItems += $info['quantity'];
        $valueOfItemsOnCart += $info['price'] * $info['quantity'];
     }
 if(!empty($_SESSION['ErroMsg'])){
     $json['error'] = 'Available quantity of '.$store->Inventory[$Item]['name'].' is less than requested quantity';
     unset($_SESSION['ErroMsg']);
 }else{
    $json['success'] = 'Success: You have added <a href="">' . $store->Inventory[$Item]['name'] . "</a> to your <a href='" . $rootpath . "/showcart.php" . "'" . ">shopping cart</a>!";
    $json['total-number'] = '<b>'.$totalnumberOfItems.'</b>' ;
    $json['total-value'] =  '<b>'.number_format($valueOfItemsOnCart,2).'</b>';
 }
    
}



$_SESSION['currentStore'] = serialize($store);

    if (isset($_POST['quantity']) && !isset($_POST['product_id'])){
        unset($_POST['quantity']);
        unset($_POST['selecteditem']);
        $extra ='';
    if(!empty($_SESSION['ErroMsg'])){
        // echo "Here...";
        // exit();
        $extra = 'showcart.php?message=1';
        header("Location:$extra");

    }else{
    $extra = 'showcart.php';
    header("Location:$extra");
    }

}else{
    echo json_encode($json);
    exit;
    unset($_POST['product_id']);
    unset($json['success']);  
}

               


?>