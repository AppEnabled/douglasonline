$(document).ready(function() {
        
        $('.success img, .warning img, .attention img, .information img').live('click', function() {
		$(this).parent().fadeOut('slow', function() {
			$(this).remove();
		});
	});	
        
});

function addToCart(product_id, quantity) {
	
	quantity = typeof(quantity) != 'undefined' ? quantity : 1;
	$.ajax({
		url: 'autoadd.php',
		type: 'post',
		data: 'product_id=' + product_id + '&quantity=' + quantity,
		dataType: 'json',
		success: function(data) {
			$('.success, .warning, .attention, .information, .error').remove();

			if (data['success']) {
				$('#notification').html('<div class="success" style="display: none;">' + data['success'] + '<img src="images/slide_images/close.png" alt="" class="close" /></div>');

				$('.success').fadeIn('slow');
				
				$('#total-number').html(data['total-number']);
                $('#total-value').html(data['total-value']);
				
				$('html, body').animate({ scrollTop: 0 }, 'slow'); 
			}	

          	if (data['error']) {
				$('#notification').html('<div class="warning" >'+ data['error'] + '<img src="images/slide_images/close.png" alt="" class="close" /></div>');
				$('.warning').fadeIn('slow');
				$('html, body').animate({ scrollTop: 0 }, 'slow'); 
			}

		}
	});
}