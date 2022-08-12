<?php
/*include our headers*/

$title = _("DougCart|CheckOut");
include 'includes/config.php';

include('includes/header.inc');
include('includes/cart.php');

if (isset($_GET['dataposted'])) {
?>
    <div id="content">

        <div id="shopping-cart-items">
            <h2>Thank you for Shopping with Douglas Online!!!!</h2>
            <?php
              $store = new Cart();
            ?>

        </div>

    </div>
<?php
    unset($_GET['dataposted']);
} else {

    if (isset($_SESSION['currentStore']))

        $store = unserialize($_SESSION['currentStore']);
    else {
        $store = new Cart();
    }


?>
<form method="post" action="checkout.php">
        <div id="content">
            <div class="breadcrumb">
            </div>
            <div id="shopping-cart-items">
                <h1>Check-Out </h1>

                <div class="checkout">
                    <!------------------------------------->
                    <div id="payment-address">
                        <div class="checkout-heading">
                            <span>Step 1:Billing Details</span>
                        </div>
                        <div class="checkout-content">
                            <div class="left">
                                <h2>Your Personal Details</h2>
                                <span class="required">*</span>
                                First Name:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['firstname']) ? $_SESSION['firstname'] : ''; ?>" name="firstname">
                                <br>
                                <br>
                                <span class="required">*</span>
                                Last Name:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['lastname']) ? $_SESSION['lastname'] : ''; ?>" name="lastname">
                                <br>
                                <br>
                                <span class="required">*</span>
                                E-Mail:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['email']) ? $_SESSION['email'] : ''; ?>" name="email">
                                <br>
                                <br>
                                <span class="required">*</span>
                                Telephone:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['telephone']) ? $_SESSION['telephone'] : ''; ?>" name="telephone">
                                <br>
                                <br>
                                Fax:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['fax']) ? $_SESSION['fax'] : ''; ?>" name="fax">
                                <br>
                                <br>
                                <h2>Your Password</h2>
                                <span class="required">*</span>
                                Password:
                                <br>
                                <input class="large-field" type="password" value="<?php echo !empty($_SESSION['password']) ? $_SESSION['password'] : ''; ?>" name="password">
                                <br>
                                <br>
                                <span class="required">*</span>
                                Password Confirm:
                                <br>
                                <input class="large-field" type="password" value="<?php echo !empty($_SESSION['comfirm']) ? $_SESSION['comfirm'] : ''; ?>" name="confirm">
                                <br>
                                <br>
                                <br>
                            </div>
                            <div class="right">
                                <h2>Your Address</h2>
                                Company:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['company']) ? $_SESSION['company'] : ''; ?>" name="company">
                                <br>
                                <br>
                                <span class="required">*</span>
                                Address 1:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['address_1']) ? $_SESSION['address_1'] : ''; ?>" name="address_1">
                                <br>
                                <br>
                                Address 2:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['address_2']) ? $_SESSION['address_2'] : ''; ?>" name="address_2">
                                <br>
                                <br>
                                <span class="required">*</span>
                                City:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['city']) ? $_SESSION['city'] : ''; ?>" name="city">
                                <br>
                                <br>
                                <span id="payment-postcode-required" class="required">*</span>
                                Post Code:
                                <br>
                                <input class="large-field" type="text" value="<?php echo !empty($_SESSION['postcode']) ? $_SESSION['postcode'] : ''; ?>" name="postcode">
                                <br>
                                <br>
                                <br>
                                <br>
                            </div>
                            <div style="clear: both; padding-top: 15px; border-top: 1px solid #EEEEEE;">
                            </div>
                            <div class="buttons">
                                <div class="right">
                                    I have read and agree to the
                                    <a class="colorbox cboxElement" alt="Terms & Conditions" href="terms.php">
                                        <b>Terms & Conditions</b>
                                    </a>
                                    <input type="checkbox" name="agree">
                                    <input id="button-personal" name="personalbutton" class="button" type="submit" value="Continue">

                                </div>
                            </div>
                        </div>
                    </div>
    </form>
    <form method="post" action="postfieds.php">
        <div id="confirm">
            <div class="checkout-heading">Step 2: Confirm Order</div>
            <div class="checkout-content">
                <div class="checkout-product">
                    <table>
                        <thead>
                            <tr>
                                <td class="name">Product Name</td>
                                <td class="model">Model</td>
                                <td class="quantity">Quantity</td>
                                <td class="price">Price</td>
                                <td class="total">Total</td>
                            </tr>
                        </thead>
                        <tbody>
                            <?php $total = 0;
                            foreach ($store->ShoppingCart as $product => $info) {

                                if ($info['quantity'] > 0) {

                            ?>
                                    <tr>
                                        <td class="name">
                                            <?php echo "<a href='" . $rootpath . "/Products.php?" . SID . "&product_id=" . $product . "'>" ?><?php echo $info['name']; ?></a>
                                        </td>
                                        <td class="model"><?php echo $info['model']; ?></td>
                                        <td class="quantity"><?php echo $info['quantity']; ?></td>
                                        <td class="price"><?php echo $info['price']; ?></td>
                                        <td class="total"><?php echo number_format(($info['price'] * $info['quantity']), 2); ?></td>
                                    </tr>
                            <?php $total += ($info['price'] * $info['quantity']);
                                }
                            } ?>
                        </tbody>
                        <tfoot>
                            <tr>
                                <td class="price" colspan="4">
                                    <b>Sub-Total:</b>
                                </td>
                                <td class="total"><?php echo number_format($total, 2); ?></td>
                            </tr>
                            <tr>
                                <td class="price" colspan="4">
                                    <b>Vat Amount:</b>
                                </td>
                                <td class="total"><?php echo number_format(($total * 0.14), 2); ?></td>
                            </tr>
                            <tr>
                                <td class="price" colspan="4">
                                    <b>Total:</b>
                                </td>
                                <td class="total">R <?php echo number_format(($total * 1.14), 2); ?></td>
                            </tr>
                        </tfoot>
                    </table>
                </div>

                <div class="payment">
                    <div class="buttons">

                        <div class="right">
                            <input id="button-confirm" name="confirmOrder" class="button" type="submit" value="Confirm Order">
                        </div>
                    </div>
                </div>
            </div>
        </div>
        </div>
        </div>

        </div>

        <?php

        if (isset($_GET['editthisdetails'])) {
        ?>
            <script type="text/javascript">
                $('#payment-address .checkout-content').slideDown('slow');
                $("#confirm .checkout-content").slideUp('slow');
            </script>
        <?php
        }
        if (!isset($_POST['personalbutton'])) {


        ?>

            <script type="text/javascript">
                $('#payment-address .checkout-content').slideDown('slow');
            </script>
        <?php } else {

            $_SESSION['firstname'] = $_POST['firstname'];
            $_SESSION['lastname'] = $_POST['lastname'];
            $_SESSION['email'] =  $_POST['email'];
            $_SESSION['telephone'] = $_POST['telephone'];
            $_SESSION['fax'] = $_POST['fax'];
            $_SESSION['confirm'] = $_POST['confirm'];
            $_SESSION['password'] = $_POST['password'];
            $_SESSION['company'] = $_POST['company'];
            $_SESSION['address_1'] = $_POST['address_1'];
            $_SESSION['address_2'] = $_POST['address_2'];
            $_SESSION['city'] = $_POST['city'];
            $_SESSION['postcode'] = $_POST['postcode'];

        ?>
            <script type="text/javascript">
                $("#confirm .checkout-content").slideDown('slow');
                $('#payment-address .checkout-content').slideUp('slow');
            </script>
    </form>

<?php
            $_SESSION['currentStore'] = serialize($store);
        }
    }
    include('includes/footer.inc'); ?>