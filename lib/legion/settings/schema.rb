# frozen_string_literal: true

module Legion
  module Settings
    class Schema
      def initialize
        @schemas = {}
        @registered = []
      end

      def register(mod_name, defaults)
        mod_name = mod_name.to_sym
        @registered << mod_name unless @registered.include?(mod_name)
        @schemas[mod_name] ||= {}
        infer_types(defaults, @schemas[mod_name])
      end

      def define_override(mod_name, overrides)
        mod_name = mod_name.to_sym
        @schemas[mod_name] ||= {}
        apply_overrides(overrides, @schemas[mod_name])
      end

      def constraint(mod_name, key_path)
        node = @schemas[mod_name.to_sym]
        key_path.each do |key|
          return nil unless node.is_a?(Hash) && node.key?(key)

          node = node[key]
        end
        node
      end

      def registered_modules
        @registered.dup
      end

      def schema_for(mod_name)
        @schemas[mod_name.to_sym]
      end

      private

      def infer_types(defaults, target)
        defaults.each do |key, value|
          target[key] ||= {}
          if value.is_a?(Hash) && !value.empty?
            infer_types(value, target[key])
          else
            target[key][:type] = infer_type(value)
          end
        end
      end

      def infer_type(value)
        case value
        when String      then :string
        when Integer     then :integer
        when Float       then :float
        when true, false then :boolean
        when Array       then :array
        when Hash        then :hash
        else :any
        end
      end

      def apply_overrides(overrides, target)
        overrides.each do |key, value|
          target[key] ||= {}
          if value.is_a?(Hash) && !value.key?(:type) && !value.key?(:required) && !value.key?(:enum)
            apply_overrides(value, target[key])
          else
            target[key].merge!(value)
          end
        end
      end
    end
  end
end
