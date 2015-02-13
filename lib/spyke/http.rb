require 'faraday'
require 'spyke/config'
require 'spyke/path'
require 'spyke/result'

module Spyke
  module Http
    extend ActiveSupport::Concern
    METHODS = %i{ get post put patch delete }

    module ClassMethods
      METHODS.each do |method|
        define_method(method) do |path, params = {}|
          new_or_collection_from_result send("#{method}_raw", path, params)
        end

        define_method("#{method}_raw") do |path, params = {}|
          request(method, path, params)
        end
      end

      def request(method, path, params = {})
        ActiveSupport::Notifications.instrument('request.spyke', method: method) do |payload|
          response = connection.send(method) do |request|
            if method == :get
              request.url path.to_s, params
            else
              request.url path.to_s
              request.body = params
            end
          end
          payload[:url], payload[:status] = response.env.url, response.status
          Result.new_from_response(response)
        end
      end

      def new_or_collection_from_result(result)
        if result.data.is_a?(Array)
          new_collection_from_result(result)
        else
          new_from_result(result)
        end
      end

      def new_from_result(result)
        new result.data if result.data
      end

      def new_collection_from_result(result)
        Collection.new Array(result.data).map { |record| new(record) }, result.metadata
      end

      def uri(uri_template = "/#{model_name.plural}/(:id)")
        @uri ||= uri_template
      end

      def connection
        Config.connection
      end
    end

    METHODS.each do |method|
      define_method(method) do |action = nil, params = {}|
        params = action if action.is_a?(Hash)
        path = resolve_path_from_action(action)

        result = self.class.send("#{method}_raw", path, params)

        add_errors_to_model(result.errors)
        self.attributes = result.data
      end
    end

    def uri
      Path.new(@uri_template, attributes)
    end

    private

      def add_errors_to_model(errors_hash)
        errors_hash.each do |field, field_errors|
          field_errors.each do |attributes|
            message, options = extract_message(attributes)
            errors.add(field.to_sym, message, options)
          end
        end
      end

      def extract_message(attributes)
        use_i18n = attributes.reverse_merge(use_i18n: true).delete(:use_i18n)
        error = attributes.delete(:error)
        message = use_i18n ? error.to_sym : error

        [message, attributes.symbolize_keys]
      end

      def resolve_path_from_action(action)
        case action
        when Symbol then uri.join(action)
        when String then Path.new(action, attributes)
        else uri
        end
      end
  end
end
