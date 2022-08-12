<?php 
session_start(); 
include_once 'includes/config.php';
?>

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
    <head>
        <title><?php echo $title; ?></title>
        <link href="styles/styles.css" rel="stylesheet" type="text/css">
        <link href="styles/slideshow.css" rel="stylesheet" type="text/css">
        <link href="jquery/colorbox/colorbox.css" rel="stylesheet" type="text/css">
        <link rel="shortcut icon" href="<?php echo $rootpath ."/images/cart.png"; ?>">
    

        <style type="text/css">
            body {
                background-color: #cccccc;
            }
        </style>
        <script type="text/javascript" src="jquery/jquery-1.7.1.min.js"></script>
        <script language="javascript" type="text/javascript" src="jquery/jquery.nivo.slider.pack.js"></script>
        <script language="javascript" type="text/javascript" src="javascripts/common.js"></script>
        <script language="javascript" type="text/javascript" src="javascripts/ajax.js"></script>
        <script language="javascript" type="text/javascript" src="javascripts/ajax-dynamic-list.js"></script>
     
        <script type="text/javascript">
            
        $(window).load(function() {              
            $.ajax({
                url: 'getItemvalues.php',
                dataType: 'json',
                success: function(json) {

                    $('#total-number').html(json['total-number']);
                    $('#total-value').html(json['total-value']);
                                        
                }//,
                //cache: false
            });
            
           });
                            
</script>
<?php
if(isset($_GET['message'])){
   unset($_GET['message']);
    $DisplayMsg = "";
    $ErroMsg = array();
   
 
    $ErroMsg = !empty($_SESSION['ErroMsg']) ? $_SESSION['ErroMsg'] : array();
    for ($i = 0; $i < count($ErroMsg); $i++) {
         $DisplayMsg =  $DisplayMsg ."<tr><td class=tdc><font color=red>". $ErroMsg[$i] ."</font></td></tr>";
    }
 
if ($DisplayMsg !=""){
echo '<table>';

 echo '<link href="' . $rootpath . '/facebox/src/facebox.css" media="screen" rel="stylesheet" type="text/css"/>';
 echo '<script src="' . $rootpath . '/facebox/src/facebox.js" type="text/javascript"></script>';

 echo "<script>jQuery.facebox('$DisplayMsg');</script>";
 echo '</table>';
}
 
 unset($_SESSION['ErroMsg']);
 unset($ErroMsg);
 unset($_GET['message']);
 
 }
?>
<script type="text/javascript">
    $(window).load(function() {
          $('#slideshow').nivoSlider();
     });
            
</script>

</head>
<body>
<div id="silver-shadow-left">
    <div id="silver-container">
    <div id="silver-header">
                    <img
                        src="images/corporate_logo.png"
                        width="317"
                        height="58"
                        alt="Online Catalogue"
                        class="logoimage" />

                    <div id="silver-login-terms">
                        <p><a href="">Login</a>&nbsp;|&nbsp;<a href="">Contact Us</a></p>
                    </div>
                    <div id="silver-cart-checkout">

                        <p><?php echo "<a href='" . $rootpath . "/showcart.php" . "'"; ?> class="silver-cart-link">View Cart</a>&nbsp;|&nbsp;<?php echo "<a href='" . $rootpath . "/checkout.php" . "'"; ?>>Checkout</a>&nbsp;|&nbsp;Items:<label id="total-number"></label>
                            , Value:<label id="total-value"></label>
                        </p>
                    </div>       
                </div>

                <div id="silver-nav-bar">
                    <div id="silver-quick-search-container">
                        <div id="silver-quick-search">
                            <div id="silver-quick-search-field">
                                <form name="simplesearch" method="post" action="">
                                    <input class="silver-search-field" name="quicksearch" type="text" value="Search the Site" onkeyup="ajax_showOptions(this,'getItem',event)" onfocus="this.value='';" autocomplete=off/><input class="silver-search-button" type="image" name="ACTION" src="images/silver-search-button.gif" />

                                    <input type="hidden" name="page" value="search" />
                                    <input type="hidden" name="PR" value="-1" />
                                    <input type="hidden" name="TB" value="A" />
                                </form>
                            </div>
                        </div>
                    </div>
                    <div id="silver-nav-bar-left">
                        <ul>
                            <li><a href="index.php">Home</a></li>
                            <li><a href="Products.php" target="_self">Products</a></li>
                            <li><a href="">Terms & Conds</a></li>
                            <li><a href="">Search</a></li>
                            <li><a href="">Contact Us</a></li>
                            <li><a href="">Site Map</a></li>
                            <li><a href="aboutus.php">About Us</a></li>
                        </ul>
                    </div>
                </div>
<div style="clear: both;"><img src="images/theme_shim.gif" height="8" alt="spacer"/></div>
<div id="notification"></div>


