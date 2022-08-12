<?php

/*
 * @author: Tamelo Douglas
 * 
 */

class Cart {
    
    public $db;
    public $Inventory = array();
    public $SelectedItem;
    public $Categories = array();
    public $CategoriesSub = array();
    public $Sub_Categories = array();
    public $ShoppingCart = array();
    public $itemsInCart = false;

    function __construct() {
        include_once ("database.php");
        $this->db = new MysqlDatabase();

    }

    /**
     * Close database on exit
     */
    function __destruct() {

        $this->db->close_connection();
    }
    
    /**
     * reconnect to the database
     */
    function __wakeup() {
        include_once ("database.php");
        $this->db = new MysqlDatabase();
    }

    /**
     * Retrieve products, limit only 6 items
     * @return array
     */
    public function getProducts() {

        $SQL = "SELECT * FROM 
                    product  
                    LIMIT 6";

        $result = $this->db->db_query($SQL);

        while ($myrow = $this->db->db_fetch_array($result)) {

            $this->Inventory[$myrow['product_id']] = array();
            $this->Inventory[$myrow['product_id']]['product_id'] = $myrow['product_id'];
            $this->Inventory[$myrow['product_id']]['name'] = $myrow['name'];
            $this->Inventory[$myrow['product_id']]['model'] ='';
            $this->Inventory[$myrow['product_id']]['description'] = $myrow['description'];
            $this->Inventory[$myrow['product_id']]['price'] = $myrow['price'];
            $this->Inventory[$myrow['product_id']]['quantity'] = $myrow['quantity'];
            $this->Inventory[$myrow['product_id']]['status'] = $myrow['status'];
        }
        return $this->Inventory;
    }

    /**
     * Add item to cart
     * @param null $item
     */
    public function addToCart($item = null) {
        $ErroMsg = array();

        if (array_key_exists($item, $this->ShoppingCart)) {
            $SQL =  "SELECT quantity FROM product 
                                       WHERE product_id = ".$item;
            $result = $this->db->db_query($SQL);
            $myrow = $this->db->db_fetch_array($result);


            if($myrow['quantity'] < $this->ShoppingCart[$item]['quantity']){
                $ErroMsg[] = "Available quantity of ".$this->ShoppingCart[$item]['name']."  is less than requested quantity";
                if (!empty($ErroMsg)) {
                    $_SESSION['ErroMsg'] = $ErroMsg;
                }
            }else{
                $this->ShoppingCart[$item]['quantity'] += 1;
            }
        }
    }

/**
 * addToCartByQty function
 *
 * @param [type] $item
 * @param [type] $product_qty
 * @return void
 */
    public function  addToCartByQty($item,$product_qty){

        if (array_key_exists($item, $this->ShoppingCart)) {

            $SQL =  "SELECT quantity FROM product 
                                       WHERE product_id = ".$item;
            $result = $this->db->db_query($SQL);
            $myrow = $this->db->db_fetch_array($result);

            if($myrow['quantity'] < $product_qty){
                $ErroMsg[] = "Available quantity of ".$this->ShoppingCart[$item]['name']."  is less than requested quantity";
                if (!empty($ErroMsg)) {

                    $_SESSION['ErroMsg'] = $ErroMsg;

                }

            }else{
                $this->ShoppingCart[$item]['quantity'] = $product_qty;
            }

        }else{
          
            $SQL =  "SELECT quantity FROM product 
                                       WHERE product_id = ".$item;
            $result = $this->db->db_query($SQL);
            $myrow = $this->db->db_fetch_array($result);

            if($myrow['quantity'] < $product_qty){

                $ErroMsg[] = "Available quantity of ".$this->ShoppingCart[$item]['name'] ." is less than requested quantity";
                if (!empty($ErroMsg)) {

                    $_SESSION['ErroMsg'] = $ErroMsg;

                }

            }else{
                $this->ShoppingCart[$item]['quantity'] = $product_qty;
            }
        }

    }

    /**
     * removeFromCart function
     *
     * @param [type] $item
     * @return void
     */
    function removeFromCart($item) {

        if (array_key_exists($item, $this->ShoppingCart)) {

            if ($this->ShoppingCart[$item]['quantity'] > 0) {
                $this->ShoppingCart[$item]['quantity']-=1;
            }
        }
    }

    public function removeFromCartAll($item) {
        if (array_key_exists($item, $this->ShoppingCart)) {

            unset($this->ShoppingCart[$item]);
        }
    }

    function emptyCart() {

        foreach ($this->ShoppingCart as $key => $value) {
            $this->ShoppingCart[$key]['quantity'] = 0;
        }
    }

    public function showcart() {
        global $rootpath;
        $total = 0;
        $itemsInCart = false;

        $displayCart = '<form  method="post" action="autoadd.php">
       <div class="cart-info">
        <table>
           <thead>
                    <tr>
                    <td class = "image">Image</td>
                    <td class = "name">Product Name</td>
                    <td class = "model">Model</td>
                    <td class = "quantity">Quantity</td>
                    <td class = "price">Unit Price</td>
                    <td class = "total">Total</td>
                    </tr>
                    </thead>
                    <tbody>';
        foreach ($this->ShoppingCart as $product => $info) {
        
            if ($info['quantity'] > 0) {
                $itemsInCart  = true;
                $total += $info['price'] * $info['quantity'];
                $displayCart .= ' <tr>
                        <td class = "image">
                        <a href = "">
                        <img title = "' . $info['name'] . '" alt = "' . $info['name'] . '" src = "images/cache/data/demo/'.$info['name'].'-47x47.jpg">
                        </a>
                        </td>
                        <td class = "name">
                        <a href = "'.$rootpath."/Products.php?&product_id=".$product.'">' . $info['name'] . '</a>
                        <div> </div>
                        </td>
                        <td class = "model">' . $info['model'] . '</td>
                        <td class = "quantity">
                        <input type = "text" size = "1" value = ' . (int) $info['quantity'] . ' name = "quantity['.$product.']">
                        <input type = "image" title = "Update" alt = "" src="images/slide_images/update.png">
                        <a href = "'.$_SERVER['SCRIPT_NAME']."?" .SID."removeFromCart=".$product.'">
                        <img title = "Remove Item" alt = "Remove Item" src = "images/slide_images/remove.png">
                        </a>
                        <a href = "'.$_SERVER['SCRIPT_NAME']."?" .SID."removeFromCartAll=".$product.'">
                        <img title = "Remove All" alt = "Remove  All" src = "images/slide_images/removeall.png">
                        </a>
                        </td>
                        <td class = "price">' . number_format($info['price'],2) . '</td>
                        <td class = "total">' . number_format(($info['price'] * $info['quantity']),2) . '</td>
                        </tr>';
          
            }
        }

        if($itemsInCart){
            echo $displayCart;

            /**Dispaly totals*/
            echo ' </tbody></table>
 
   </div>
           
 </form>  
   <div class="cart-total">
        <table id="total">
            <tbody>
                <tr>
                   
                    <td class="right">'.number_format($total,2).'</td>
                     <td class="right">
                        <b>Sub-Total:</b>
                    </td>
                </tr>
               
                <tr>
                   
                    <td class="right">'.number_format(($total*0.14),2).'</td>
                     <td class="right">
                        <b>Vat Amt(14%):</b>
                    </td>
                </tr>
                <tr>
                    
                    <td class="right">'.number_format(($total*1.14),2).'</td>
                    <td class="right">
                        <b>Total:</b>
                    </td>
                </tr>
            </tbody>
        </table>
    </div>';
            /***************************/
            include 'includes/config.php';
            echo '<div class="buttons">
    <div class="right">
        <a class="button" href="'.$rootpath ."/checkout.php".'">Checkout</a>
    </div>';

            echo '<div class="center">
        <a class="button" href="'.$rootpath."/Products.php".'">Continue Shopping</a>
    
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
        <a class="button" href="'.$_SERVER['SCRIPT_NAME']."?" .SID."emptyCart=1".'">Empty Cart</a>
           
    </div>
  </div> ';

        }else{
            echo "<div class=\"content\"><font size=3><b>Your shopping cart is empty!</b></font></div>";
        }
    }

    public function getProduct($Productid = 0) {

        $SQL = "SELECT * FROM 
                    product
                    WHERE product.product_id = " . $Productid ;


        $result = $this->db->db_query($SQL);
        $myrow = $this->db->db_fetch_array($result);
        $this->Inventory[$myrow['product_id']] = array();

        $this->Inventory[$myrow['product_id']]['product_id'] = $myrow['product_id'];
        $this->Inventory[$myrow['product_id']]['name'] = $myrow['name'];
        $this->Inventory[$myrow['product_id']]['model'] = $myrow['model'];
        $this->Inventory[$myrow['product_id']]['description'] = $myrow['description'];
        $this->Inventory[$myrow['product_id']]['price'] = $myrow['price'];
        $this->Inventory[$myrow['product_id']]['quantity'] = $myrow['quantity'];
        $this->Inventory[$myrow['product_id']]['status'] = $myrow['status'];

        if (!array_key_exists($myrow['product_id'], $this->ShoppingCart)) {
            $this->ShoppingCart[$myrow['product_id']]['quantity'] = 0;
            $this->ShoppingCart[$myrow['product_id']]['price'] = $myrow['price'];
            $this->ShoppingCart[$myrow['product_id']]['description'] = $myrow['description'];
            $this->ShoppingCart[$myrow['product_id']]['name'] = $myrow['name'];
            $this->ShoppingCart[$myrow['product_id']]['model'] = $myrow['model'];
            $this->ShoppingCart[$myrow['product_id']]['status'] = $myrow['status'];
        }


        return $this->Inventory;
    }



    public function getProductByCategory($category) {

        $SQL = "SELECT * FROM   
                    product,product_to_category,product_description
                    WHERE  product.product_id = product_to_category.product_id
                    AND product_description.product_id = product.product_id 
                    AND product_to_category.category_id = " . $category;
        $result = $this->db->db_query($SQL);

        while ($myrow = $this->db->db_fetch_array($result)) {
            $this->Inventory[$myrow['product_id']] = array();
            $this->Inventory[$myrow['product_id']]['product_id'] = $myrow['product_id'];
            $this->Inventory[$myrow['product_id']]['name'] = $myrow['name'];
            $this->Inventory[$myrow['product_id']]['description'] = $myrow['description'];
            $this->Inventory[$myrow['product_id']]['price'] = $myrow['price'];
            $this->Inventory[$myrow['product_id']]['quantity'] = $myrow['quantity'];
            $this->Inventory[$myrow['product_id']]['image'] = $myrow['image'];
            $this->Inventory[$myrow['product_id']]['status'] = $myrow['status'];


            if (!array_key_exists($myrow['product_id'], $this->ShoppingCart)) {
                $this->ShoppingCart[$myrow['product_id']]['quantity'] = 0;
                $this->ShoppingCart[$myrow['product_id']]['price'] = $myrow['price'];
                $this->ShoppingCart[$myrow['product_id']]['image'] = $myrow['image'];
                $this->ShoppingCart[$myrow['product_id']]['description'] = $myrow['description'];
            }
        }
        return $this->Inventory;
    }

    /** 
     * Add customer info
     * create order/invoice
     */
    public function addCustInformation($firstname,$lastname,$email,$telephone,
                                       $fax,$password,$company,$address_1,$address_2,$city,$postcode){

        $result = false;
        foreach ($this->ShoppingCart as $product => $info) {

            if ($info['quantity'] > 0) {
                /*Now decrease the inventory quantities*/
                $SQL =  "UPDATE product SET quantity = quantity-".$info['quantity']."
                                       WHERE product_id = ".$product;
                $result =   $this->db->db_query($SQL);
            }

        }
        return $result;
    }
}

?>
