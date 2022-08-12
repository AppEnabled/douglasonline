<?php

/*Tamelo Douglas 
 * Get values
 * Last date edited:2022
 */
session_start();
include_once 'includes/config.php';
include('includes/cart.php');
header("Content-type: text/json");


if (isset($_SESSION['currentStore'])) {
    $store = unserialize($_SESSION['currentStore']);

} else {
    $store = new Cart();
   
}
    $json = array();

    $totalnumberOfItems = 0;
    $valueOfItemsOnCart = 0;
    
  foreach ($store->ShoppingCart as $product => $info) {
        $totalnumberOfItems += $info['quantity'];
        $valueOfItemsOnCart += $info['price'] * $info['quantity'];
     }
    $json['total-number'] = '<b>'.$totalnumberOfItems.'</b>';
    $json['total-value'] =  '<b>'.number_format($valueOfItemsOnCart,2).'</b>';
    
$_SESSION['currentStore'] = serialize($store);
echo json_encode($json);
