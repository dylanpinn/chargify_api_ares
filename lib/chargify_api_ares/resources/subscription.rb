module Chargify
  class Subscription < Base
    def self.find_by_customer_reference(reference)
      customer = Customer.find_by_reference(reference)
      find(:first, :params => {:customer_id => customer.id})
    end

    # Strip off nested attributes of associations before saving, or type-mismatch errors will occur
    def save
      self.attributes.delete('customer')
      self.attributes.delete('product')
      self.attributes.delete('credit_card')
      super
    end

    def cancel
      destroy
    end

    def component(id)
      Component.find(id, :params => {:subscription_id => self.id})
    end

    def components(params = {})
      params.merge!({:subscription_id => self.id})
      Component.find(:all, :params => params)
    end
    
    def events(params = {})
      params.merge!(:subscription_id => self.id)
      Event.all(:params => params)
    end

    def payment_profile
      self.respond_to?('credit_card') ? credit_card : nil
    end

    def hosted_page_url(page)
      url = nil
      if self.respond_to?('id')
        # Generate 10 character SHA1 token
        token_string = "#{page}--#{self.id}--#{Chargify.shared_key}"
        token = Digest::SHA1.hexdigest(token_string)[0..9]
        # Format URL for page
        url = "https://#{Chargify.subdomain}.chargify.com/#{page}/#{self.id}/#{token}"
      end
      url
    end

    def hosted_update_payment_page_url
      self.hosted_page_url('update_payment')
    end

    # Perform a one-time charge on an existing subscription.
    # For more information, please see the one-time charge API docs available
    # at: http://support.chargify.com/faqs/api/api-charges
    def charge(attrs = {})
      post :charges, {}, attrs.to_xml(:root => :charge)
    end

    def credit(attrs = {})
      post :credits, {}, attrs.to_xml(:root => :credit)
    end

    def refund(attrs = {})
      post :refunds, {}, attrs.to_xml(:root => :refund)
    end

    def reactivate(params = {})
      put :reactivate, params
    end

    def reset_balance
      put :reset_balance
    end

    def migrate(attrs = {})
      post :migrations, :migration => attrs
    end

    def migrate_preview(attrs = {})
      api_url = "https://#{Chargify.subdomain}.chargify.com/subscriptions/#{self.id}/migrations/preview.xml"
      data = attrs.to_xml(:root => :migration, :dasherize => false, :skip_types => true).tr("\n", "").strip
      response = connection.post(api_url, :body => data, :basic_auth => {:username => Chargify.api_key, :password => 'X'})
      response_xml = Hash.from_xml(response.body)
      response_xml["migration"]
    end

    def statement(id)
      statement = Chargify::Statement.find(id)
      raise ActiveResource::ResourceNotFound.new(nil) if (statement.subscription_id != self.id)
      statement
    end

    def statements(params = {})
      params.merge!(:subscription_id => self.id)
      Statement.find(:all, :params => params)
    end

    def transactions(params = {})
      params.merge!(:subscription_id => self.id)
      Transaction.find(:all, :params => params)
    end

    def adjustment(attrs = {})
      post :adjustments, {}, attrs.to_xml(:root => :adjustment)
    end

    def add_coupon(code)
      post :add_coupon, :code => code
    end

    def remove_coupon(code=nil)
      if code.nil?
        delete :remove_coupon
      else
        delete :remove_coupon, :code => code
      end
    end

    class Component < Base
      self.prefix = "/subscriptions/:subscription_id/"

      # All Subscription Components are considered already existing records, but the id isn't used
      def id
        self.component_id
      end
    end

    class Event < Base
      self.prefix = '/subscriptions/:subscription_id/'
    end
    
    class Statement < Base
      self.prefix = "/subscriptions/:subscription_id/"
    end

    class Transaction < Base
      self.prefix = "/subscriptions/:subscription_id/"

      def full_refund(attrs = {})
        return false if self.transaction_type != 'payment'

        attrs.merge!(:amount_in_cents => self.amount_in_cents)
        self.refund(attrs)
      end

      def refund(attrs = {})
        return false if self.transaction_type != 'payment'

        attrs.merge!(:payment_id => self.id)
        Subscription.find(self.prefix_options[:subscription_id]).refund(attrs)
      end
    end
  end
end
