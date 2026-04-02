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

      def validate_module(mod_name, values)
        mod_name = mod_name.to_sym
        mod_schema = @schemas[mod_name]
        return [] if mod_schema.nil?

        errors = []
        validate_node(mod_schema, values, mod_name, '', errors)
        errors
      end

      TYPE_NAMES = { string: 'String', integer: 'Integer', float: 'Float', boolean: 'Boolean',
                     array: 'Array', hash: 'Hash' }.freeze

      def detect_unknown_keys(settings, known_defaults: [])
        warnings = []
        all_known = @registered + known_defaults

        settings.each_key do |key|
          next if all_known.include?(key)

          suggestion = find_similar(key, all_known)
          msg = "top-level key :#{key} is not registered by any module"
          msg += " (did you mean :#{suggestion}?)" if suggestion
          warnings << { module: :unknown_key, path: key.to_s, message: msg }
        end

        check_first_level_keys(settings, warnings)
        warnings
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

      def validate_node(schema_node, value_node, mod_name, path_prefix, errors)
        schema_node.each do |key, constraint|
          current_path = path_prefix.empty? ? key.to_s : "#{path_prefix}.#{key}"
          value = value_node.is_a?(Hash) ? value_node[key] : nil

          if constraint.is_a?(Hash) && constraint.key?(:type)
            validate_leaf(constraint, value, mod_name, current_path, errors)
          elsif constraint.is_a?(Hash)
            next if value.nil?

            if value.is_a?(Hash)
              validate_node(constraint, value, mod_name, current_path, errors)
            else
              errors << { module: mod_name, path: current_path,
                          message: "expected Hash, got #{value.class} (#{value.inspect})" }
            end
          end
        end
      end

      def validate_leaf(constraint, value, mod_name, path, errors)
        if value.nil?
          errors << { module: mod_name, path: path, message: 'is required but was nil' } if constraint[:required]
          return
        end

        validate_type(constraint, value, mod_name, path, errors)
        validate_enum(constraint, value, mod_name, path, errors)
      end

      def validate_type(constraint, value, mod_name, path, errors)
        expected = constraint[:type]
        return if expected == :any

        valid = case expected
                when :string  then value.is_a?(String)
                when :integer then value.is_a?(Integer)
                when :float   then value.is_a?(Float) || value.is_a?(Integer)
                when :boolean then value.is_a?(TrueClass) || value.is_a?(FalseClass)
                when :array   then value.is_a?(Array)
                when :hash    then value.is_a?(Hash)
                else true
                end
        return if valid

        type_name = TYPE_NAMES.fetch(expected, expected.to_s)
        errors << { module: mod_name, path: path, message: "expected #{type_name}, got #{value.class} (#{value.inspect})" }
      end

      def validate_enum(constraint, value, mod_name, path, errors)
        return unless constraint[:enum]
        return if constraint[:enum].include?(value)

        errors << { module: mod_name, path: path, message: "expected one of #{constraint[:enum].inspect}, got #{value.inspect}" }
      end

      def check_first_level_keys(settings, warnings)
        @schemas.each do |mod_name, mod_schema|
          values = settings[mod_name]
          next unless values.is_a?(Hash)

          known_keys = mod_schema.keys
          values.each_key do |key|
            next if known_keys.include?(key)

            suggestion = find_similar(key, known_keys)
            msg = "unknown key :#{key}"
            msg += " (did you mean :#{suggestion}?)" if suggestion
            warnings << { module: mod_name, path: "#{mod_name}.#{key}", message: msg }
          end
        end
      end

      def find_similar(key, candidates)
        key_str = key.to_s
        candidates.map(&:to_s).select { |c| levenshtein(key_str, c) <= 2 }
                              .min_by { |c| levenshtein(key_str, c) }
                              &.to_sym
      end

      def levenshtein(str_a, str_b)
        m = str_a.length
        n = str_b.length
        return m if n.zero?
        return n if m.zero?

        matrix = Array.new(m + 1) { |i| i }
        (1..n).each do |j|
          prev = matrix[0]
          matrix[0] = j
          (1..m).each do |i|
            cost = str_a[i - 1] == str_b[j - 1] ? 0 : 1
            temp = matrix[i]
            matrix[i] = [matrix[i] + 1, matrix[i - 1] + 1, prev + cost].min
            prev = temp
          end
        end
        matrix[m]
      end
    end
  end
end
