<?php 
/*include our headers*/

$title = _("DougCart|Home");

include('includes/header.inc') ;
include('includes/config.php');
include('includes/cart.php');



if (isset($_SESSION['currentStore']))
    
    $store = unserialize($_SESSION['currentStore']);
else {
    $store = new Cart();
}

include('includes/shoppingcart.php');

?>


<?php
$_SESSION['currentStore'] = serialize($store);
include('includes/footer.inc');?>