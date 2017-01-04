require 'spyke/collection'
require 'spyke/attributes'

module Spyke
  module AttributeAssignment
    extend ActiveSupport::Concern

    included do
      attr_reader :attributes
      delegate :[], :[]=, to: :attributes
    end

    module ClassMethods
      # By adding instance methods via an included module,
      # they become overridable with "super".
      # http://thepugautomatic.com/2013/07/dsom/
      def attributes(*names)
        unless @spyke_instance_method_container
          @spyke_instance_method_container = Module.new
          include @spyke_instance_method_container
        end

        @spyke_instance_method_container.module_eval do
          names.each do |name|
            define_method(name) do
              attribute(name)
            end
          end
        end
      end
    end

    def initialize(attributes = {})
      self.attributes = attributes
      @uri_template = scope.uri
      yield self if block_given?
    end

    def attributes=(new_attributes)
      @attributes ||= Attributes.new(scope.params)
      use_setters(new_attributes) if new_attributes
    end

    def id
      attributes[primary_key]
    end

    def id=(value)
      attributes[primary_key] = value if value.present?
    end

    def hash
      id.hash
    end

    def ==(other)
      other.instance_of?(self.class) && id? && id == other.id
    end
    alias :eql? :==

    def inspect
      "#<#{self.class}(#{@uri_template}) id: #{id.inspect} #{inspect_attributes}>"
    end

    def as_json(options = nil)
      attributes.as_json(options)
    end

    private

      def use_setters(attributes)
        # Set id attribute directly if using a custom primary key alongside an attribute named "id" to avoid clobbering
        set_attribute :id, attributes.delete(:id) if conflicting_ids?(attributes)

        attributes.each do |key, value|
          send "#{key}=", value
        end
      end

      def conflicting_ids?(attributes)
        primary_key != :id && attributes.key?(:id) && attributes.key?(primary_key)
      end

      def method_missing(name, *args, &block)
        return association(name).load  if association?(name) && args.length == 0
        return attribute(name)         if attribute?(name)   && args.length == 0
        return predicate(name)         if predicate?(name)   && args.length == 0
        return set_attribute(name, args.first) if setter?(name) && args.length == 1
        raise(ArgumentError) if (association?(name) || attribute?(name) || predicate?(name) || setter?(name))
        super
      end

      def respond_to_missing?(name, include_private = false)
        association?(name) || attribute?(name) || predicate?(name) || super
      end

      def association?(name)
        associations.has_key?(name)
      end

      def association(name)
        associations[name].build(self)
      end

      def attribute?(name)
        attributes.has_key?(name)
      end

      def attribute(name)
        attributes[name]
      end

      def predicate?(name)
        name.to_s.end_with?('?')
      end

      def predicate(name)
        !!attribute(depredicate(name))
      end

      def depredicate(name)
        name.to_s.chomp('?').to_sym
      end

      def setter?(name)
        name.to_s.end_with?('=')
      end

      def set_attribute(name, value)
        attributes[name.to_s.chomp('=')] = value
      end

      def inspect_attributes
        attributes.except(primary_key).map { |k, v| "#{k}: #{v.inspect}" }.join(' ')
      end
  end
end
