<div id="content">        
    <div class="breadcrumb">
</div>

<div id="shopping-cart-items">
<h1>Shopping Cart </h1>

    <?php 
    if(isset($_GET['removeFromCart'] )){
        $store->removefromcart($_GET['removeFromCart']);
     
    }
     if(isset($_GET['removeFromCartAll'])){
        $store->removefromcartall($_GET['removeFromCartAll']);
    }
    
     if(isset($_GET['emptyCart'])){
       $store->emptycart();
        
    }
     
     $store->showcart();

    ?>
    
</div>
</div>