<?php
/*include our headers*/

$title = _("DougCart|Home");
include('includes/header.inc') ;
include('includes/cart.php');

if (isset($_SESSION['currentStore'])) {
    $store = unserialize($_SESSION['currentStore']);
}else {
    $store = new Cart(); //instantiate if, not serialized data
}

    $store->getProducts(); //get products

?>

    <div class="slideshow">
        <div id="slideshow" class="nivoSlider" style="margin-left:10px;width: 980px; height: 280px; position: relative; ">

            <img src="images/banners/slide3.jpg" alt="" />
            <img src="images/banners/slide4.jpg" alt="" />
            <img src="images/banners/slide5.jpg" alt="" />
        </div>
    </div>
    <div class="box">
        <div class="box-heading">Featured</div>
        <div class="box-content">
            <div class="box-product">

                <?php
                $items = 0;
                foreach($store->Inventory as $ID =>$product){
                    if($items < 6){
                        ?>

                        <div>
                            <div class="image">
                                <?php echo "<a href='".$rootpath ."/Products.php?". SID ."&product_id=".$ID."'>"?><img src = "images/cache/data/demo/<?php echo $product['name'];?>-80x80.jpg" alt="<?php echo  $product['name'];?>" /></a></div>
                            <div class="name"><a href="<?php echo $rootpath ."/Products.php?". SID ."&product_id=".$ID  ; ?>"><?php echo $product['name'];?></a></div>
                            <div class="price">
                                R <?php echo number_format($product['price'],2); ?>
                            </div>
                            <div class="cart"><input type="button" value="Add to Cart" onclick="addToCart('<?php echo $ID; ?>');" class="button" /></div>
                        </div>

                    <?php }
                    $items++;
                }
                ?>

            </div></div></div>

<?php
$_SESSION['currentStore'] = serialize($store);
include('includes/footer.inc');?>