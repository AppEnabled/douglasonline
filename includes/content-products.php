<div id="silver-bulk">
  <div id="silver-bulk-bottom">
    <div id="silver-bulk-top">
      <div class="box">
        <div class="box-heading">All Products</div>
        <div class="box-content">
          <div class="box-product">

            <?php foreach ($store->Inventory as $ID => $product) { ?>

              <div>
                <div class="image">
                  <?php echo "<a href='" . $rootpath . "/Products.php?" . SID . "&product_id=" . $ID . "'>" ?><img src="images/cache/data/demo/<?php echo  $product['name']; ?>-80x80.jpg" alt="<?php echo  $product['name']; ?>" /></a></div>
                <div class="name"><a href="<?php echo $rootpath . "/Products.php?" . SID . "&product_id=" . $ID; ?>"><?php echo $product['name']; ?></a></div>
                <div class="price">
                  R <?php echo number_format($product['price'], 2); ?>
                </div>
                <div class="cart"><input type="button" value="Add to Cart" onclick="addToCart('<?php echo $ID; ?>');" class="button" /></div>
              </div>

            <?php } ?>

          </div>
        </div>
      </div>
    </div>
  </div>
</div>