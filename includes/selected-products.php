<div id="silver-bulk">
    <div id="silver-bulk-bottom">
        <div id="silver-bulk-top">
            <div class="box">
                <form  method="post" action="postfieds.php">
                <div class="box-heading">Selected Product</div>
                    <h1> <?php echo $store->Inventory[$selected_prod]['name'];  ?></h1>
                    <div class="product-info">
                        <div class="left">
                            <div class="image">
                                <a class="colorbox cboxElement" rel="colorbox" title="<?php echo $store->Inventory[$selected_prod]['name']; ?>" href="images/cache/data/demo/<?php echo $store->Inventory[$selected_prod]['name']; ?>-500x500.jpg">
                                    <img id="image" alt="<?php echo $store->Inventory[$selected_prod]['name']; ?>" title="<?php echo $store->Inventory[$selected_prod]['name']; ?>" src = "images/cache/data/demo/<?php echo $store->Inventory[$selected_prod]['name']; ?>-228x228.jpg">
                                </a>
                            </div>
                      
                        </div>
                        <div class="right">
                            <div class="description">
                                <span>Brand:</span>
                                <a href=""><?php echo $store->Inventory[$selected_prod]['model'];  ?></a>
                                <br>
                                <span>Product Code:</span>
                                <?php echo $store->Inventory[$selected_prod]['product_id'];  ?>
                                <br>
                                <span>Availability:</span>
                                <?php echo $store->Inventory[$selected_prod]['quantity'];  ?>
                            </div>
                            <div class="price">
                                Price: R <?php echo number_format($store->Inventory[$selected_prod]['price'],2);  ?>
                                <br>
                                <span class="price-tax">Inc Vat: R <?php echo number_format(($store->Inventory[$selected_prod]['price']*1.14),2);  ?></span>
                                <br>
                            </div>
                            <div class="cart">
                                <div>
                                    Qty:
                                    <input type="text"  size="2" name="selectquantity[<?php echo  $store->Inventory[$selected_prod]['product_id']; ?>]">
                                    
                                    <input id="button-cart" class="button" type="submit" name="selecteditem" value="Add to Cart">
                                </div>
                            </div>
                      
                        </div>
                        
                    </div>
                  
                    <div class="dotted_line_blue" colspan="1">
                            <img width="1" height="1" alt=" " src="../images/theme_shim.gif">
                    </div>
                    <br />
                    <p><?php echo html_entity_decode($store->Inventory[$selected_prod]['description']);  ?></p>
                </form>
                </div></div>
        </div>
   
</div>