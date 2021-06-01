require 'active_support/core_ext/hash/slice'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class StripePaymentIntentsGateway < StripeGateway
      ALLOWED_METHOD_STATES = %w[automatic manual].freeze
      ALLOWED_CANCELLATION_REASONS = %w[duplicate fraudulent requested_by_customer abandoned].freeze
      CREATE_INTENT_ATTRIBUTES = %i[description statement_descriptor receipt_email save_payment_method]
      CONFIRM_INTENT_ATTRIBUTES = %i[receipt_email return_url save_payment_method setup_future_usage off_session]
      UPDATE_INTENT_ATTRIBUTES = %i[description statement_descriptor receipt_email setup_future_usage]
      DEFAULT_API_VERSION = '2019-05-16'

      def create_intent(money, payment_method, options = {})
        post = {}
        add_amount(post, money, options, true)
        add_capture_method(post, options)
        add_confirmation_method(post, options)
        add_customer(post, options)
        add_payment_method_token(post, payment_method, options)
        add_metadata(post, options)
        add_return_url(post, options)
        add_connected_account(post, options)
        add_shipping_address(post, options)
        setup_future_usage(post, options)

        CREATE_INTENT_ATTRIBUTES.each do |attribute|
          add_whitelisted_attribute(post, options, attribute)
        end

        commit(:post, 'payment_intents', post, options)
      end

      def authorize(money, payment_method, options = {})
        create_intent(money, payment_method, options)
      end

      def show_intent(intent_id, options)
        commit(:get, "payment_intents/#{intent_id}", nil, options)
      end

      def confirm_intent(intent_id, payment_method, options = {})
        post = {}
        add_payment_method_token(post, payment_method, options)
        CONFIRM_INTENT_ATTRIBUTES.each do |attribute|
          add_whitelisted_attribute(post, options, attribute)
        end

        commit(:post, "payment_intents/#{intent_id}/confirm", post, options)
      end

      def create_payment_method(payment_method, options = {})
        post = {}
        post[:type] = 'card'
        post[:card] = {}
        post[:card][:number] = payment_method.number
        post[:card][:exp_month] = payment_method.month
        post[:card][:exp_year] = payment_method.year
        post[:card][:cvc] = payment_method.verification_value if payment_method.verification_value

        commit(:post, 'payment_methods', post, options)
      end

      def capture(money, intent_id, options = {})
        post = {}
        post[:amount_to_capture] = money
        add_connected_account(post, options)
        commit(:post, "payment_intents/#{intent_id}/capture", post, options)
      end

      def update_intent(money, intent_id, payment_method, options = {})
        post = {}
        post[:amount] = money if money

        add_payment_method_token(post, payment_method, options)
        add_payment_method_types(post, options)
        add_customer(post, options)
        add_metadata(post, options)
        add_shipping_address(post, options)
        add_connected_account(post, options)

        UPDATE_INTENT_ATTRIBUTES.each do |attribute|
          add_whitelisted_attribute(post, options, attribute)
        end

        commit(:post, "payment_intents/#{intent_id}", post, options)
      end

      def void(intent_id, options = {})
        post = {}
        post[:cancellation_reason] = options[:cancellation_reason] if ALLOWED_CANCELLATION_REASONS.include?(options[:cancellation_reason])
        commit(:post, "payment_intents/#{intent_id}/cancel", post, options)
      end

      def refund(money, intent_id, options = {})
        intent = commit(:get, "payment_intents/#{intent_id}", nil, options)
        charge_id = intent.params.dig('charges', 'data')[0].dig('id')
        super(money, charge_id, options)
      end

      private

      def add_whitelisted_attribute(post, options, attribute)
        post[attribute] = options[attribute] if options[attribute]
        post
      end

      def add_capture_method(post, options)
        capture_method = options[:capture_method].to_s
        post[:capture_method] = capture_method if ALLOWED_METHOD_STATES.include?(capture_method)
        post
      end

      def add_confirmation_method(post, options)
        confirmation_method = options[:confirmation_method].to_s
        post[:confirmation_method] = confirmation_method if ALLOWED_METHOD_STATES.include?(confirmation_method)
        post
      end

      def add_customer(post, options)
        customer = options[:customer].to_s
        post[:customer] = customer if customer.start_with?('cus_')
        post
      end

      def add_return_url(post, options)
        return unless options[:confirm]
        post[:confirm] = options[:confirm]
        post[:return_url] = options[:return_url] if options[:return_url]
        post
      end

      def add_payment_method_token(post, payment_method, options)
        return if payment_method.nil?

        if payment_method.is_a?(ActiveMerchant::Billing::CreditCard)
          p = create_payment_method(payment_method, options)
          payment_method = p.params['id']
        end

        if payment_method.is_a?(StripePaymentToken)
          post[:payment_method] = payment_method.payment_data['id']
        elsif payment_method.is_a?(String)
          post[:payment_method] = payment_method
        end
      end

      def add_payment_method_types(post, options)
        payment_method_types = options[:payment_method_types] if options[:payment_method_types]
        return if payment_method_types.nil?

        post[:payment_method_types] = Array(payment_method_types)
        post
      end

      def setup_future_usage(post, options = {})
        post[:setup_future_usage] = options[:setup_future_usage] if %w( on_session off_session ).include?(options[:setup_future_usage])
        post[:off_session] = options[:off_session] if options[:off_session] && options[:confirm] == true
      end

      def add_connected_account(post, options = {})
        return unless transfer_data = options[:transfer_data]
        post[:transfer_data] = {}
        post[:transfer_data][:destination] = transfer_data[:destination] if transfer_data[:destination]
        post[:transfer_data][:amount] = transfer_data[:amount] if transfer_data[:amount]
        post[:on_behalf_of] = options[:on_behalf_of] if options[:on_behalf_of]
        post[:transfer_group] = options[:transfer_group] if options[:transfer_group]
        post[:application_fee_amount] = options[:application_fee] if options[:application_fee]
        post
      end

      def add_shipping_address(post, options = {})
        return unless shipping = options[:shipping]
        post[:shipping] = {}
        post[:shipping][:address] = {}
        post[:shipping][:address][:line1] = shipping[:address][:line1]
        post[:shipping][:address][:city] = shipping[:address][:city] if shipping[:address][:city]
        post[:shipping][:address][:country] = shipping[:address][:country] if shipping[:address][:country]
        post[:shipping][:address][:line2] = shipping[:address][:line2] if shipping[:address][:line2]
        post[:shipping][:address][:postal_code] = shipping[:address][:postal_code] if shipping[:address][:postal_code]
        post[:shipping][:address][:state] = shipping[:address][:state] if shipping[:address][:state]

        post[:shipping][:name] = shipping[:name]
        post[:shipping][:carrier] = shipping[:carrier] if shipping[:carrier]
        post[:shipping][:phone] = shipping[:phone] if shipping[:phone]
        post[:shipping][:tracking_number] = shipping[:tracking_number] if shipping[:tracking_number]
        post
      end
    end
  end
end
