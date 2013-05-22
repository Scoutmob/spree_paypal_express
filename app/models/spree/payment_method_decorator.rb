module Spree
  PaymentMethod.class_eval do
    def paypal_express?
      method_type.start_with?('paypalexpress')
    end
  end
end
