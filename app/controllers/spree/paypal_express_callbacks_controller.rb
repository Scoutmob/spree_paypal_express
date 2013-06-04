module Spree
  class PaypalExpressCallbacksController < Spree::BaseController
    include ActiveMerchant::Billing::Integrations
    skip_before_filter :verify_authenticity_token

    ssl_required

    def notify
      retrieve_details #need to retreive details first to ensure ActiveMerchant gets configured correctly.

      @notification = Paypal::Notification.new(request.raw_post)

      # we only care about eChecks (for now?)
      if @notification.params["payment_type"] == "echeck" && @notification.acknowledge && @payment && @order.total >= @payment.amount
        @payment.started_processing!
        @payment.log_entries.create(:details => @notification.to_yaml)

        case @notification.params["payment_status"]
          when "Denied"
            @payment.failure!

          when "Completed"
            @payment.complete!
        end

      end

      render :nothing => true
    end

    def shipping_estimate
      #details from Paypal
      if request.post?
        @method = params[:METHOD]
        @version = params[:CALLBACKVERSION]
        @token = params[:TOKEN]
        @currency = params[:CURRENCYCODE]
        @locale = params[:LOCALECODE]
        @street = params[:SHIPTOSTREET]
        @street2 = params[:SHIPTOSTREET2]
        @city = params[:SHIPTOCITY]
        @state = params[:SHIPTOSTATE]
        @country = params[:SHIPTOCOUNTRY]
        @zip = params[:SHIPTOZIP]
      end
      #available shipping based on paypal details
      estimate_shipping_and_taxes

      payment_methods_atts2 = {}
      @shipping_and_taxes.each_with_index do |(shipping_method, shipping_cost, tax_total), idx|
        payment_methods_atts2["L_TAXAMT#{idx}"]                   = tax_total
        payment_methods_atts2["L_SHIPPINGOPTIONAMOUNT#{idx}"]     = shipping_cost
        payment_methods_atts2["L_SHIPPINGOPTIONNAME#{idx}"]       = shipping_method.name
        payment_methods_atts2["L_SHIPPINGOPTIONLABEL#{idx}"]      = "Shipping" #Do not change, required field
        payment_methods_atts2["L_SHIPPINGOPTIONISDEFAULT#{idx}"] = (idx == 0 ? true : false)
      end

      #compiles NVP query used by paypal callback
      query = payment_methods_atts2.inject('METHOD=CallbackResponse&CALLBACKVERSION=61&OFFERINSURANCEOPTION=false')  { |string, pair| string + '&' + pair[0].to_s + '=' + pair[1].to_s }

     render :text => query #query read by PayPal
   end

    private
      def retrieve_details
        @order = Spree::Order.find_by_number(params["invoice"])

        if @order
          @payment = @order.payments.where(:state => "pending", :source_type => "PaypalAccount").try(:first)

          @payment.try(:payment_method).try(:provider) #configures ActiveMerchant
        end
      end

      def estimate_shipping_and_taxes
        @order = Spree::Order.find_by_number(params[:id])
        #TODO remove hard coded shipping
        #Make a deep copy of the order object then stub out the parts required to get a shipping quote
        @shipping_order = Marshal::load(Marshal.dump(@order)) #Make a deep copy of the order object
        @shipping_order.ship_address = Spree::Address.new(
          :address1   => @street,
          :address2   => @street2,
          :city       => @city,
          :state      => Spree::State.find_by_abbr(@state.upcase),
          :country    => Spree::Country.find_by_iso(@country),
          :zipcode    => @zip)

        shipment = Spree::Shipment.new(:address => @shipping_order.ship_address)
        @shipping_order.ship_address.shipments<<shipment
        @shipping_order.shipments<<shipment

        free_shipping = @order.adjustments.promotion.any? do |adj|
          adj.originator.calculator.kind_of?(Spree::Calculator::FreeShipping) and
          adj.originator.promotion.eligible?(@order)
        end

        @shipping_and_taxes = @shipping_order.rate_hash.map do |shipping_method|
          #TODO need to calculate based on shipping method
          tax_total = TaxRate.match(@shipping_order).sum do |rate|
            rate.compute_amount(@shipping_order)
          end
          shipping_cost = free_shipping ? 0 : shipping_method.cost
          [shipping_method, shipping_cost, tax_total]
        end
      end

  end
end
