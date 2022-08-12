<?php
/* include our headers */

$title = _("DougCart|Products");
include('includes/header.inc');
include('includes/config.php');
include('includes/cart.php');

if (isset($_SESSION['currentStore']))
   $store = unserialize($_SESSION['currentStore']);
else {
    $store = new Cart();
}

$category_id = "";

 $selected_prod = 0;

if (isset($_GET['getchild_id'])) {

    $category_id = $_GET['getchild_id'];
}

if(isset($_GET['product_id'])){
  
    $selected_prod = $_GET['product_id'];
}

if($category_id == "" &&  $selected_prod=="")
{
    $store->getProducts();
    include('includes/content-products.php');
    
}elseif($selected_prod !=''|| $selected_prod != 0){
    
    $store->getProduct($_GET['product_id']);
    include('includes/selected-products.php');
    
}
/* Displays the footer */
include('includes/footer.inc');
?>

