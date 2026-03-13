# frozen_string_literal: true

require 'legion/json'
require 'legion/settings/version'
require 'legion/json/parse_error'
require 'legion/settings/loader'
require 'legion/settings/schema'
require 'legion/settings/validation_error'

module Legion
  module Settings
    CORE_MODULES = %i[transport cache crypt data logging client].freeze

    class << self
      attr_accessor :loader

      def load(options = {})
        @loader = Legion::Settings::Loader.new
        @loader.load_env
        @loader.load_file(options[:config_file]) if options[:config_file]
        @loader.load_directory(options[:config_dir]) if options[:config_dir]
        options[:config_dirs]&.each do |directory|
          @loader.load_directory(directory)
        end
        @loader
      end

      def get(options = {})
        @loader || @loader = load(options)
      end

      def [](key)
        logger.info('Legion::Settings was not loading, auto loading now!') if @loader.nil?
        @loader = load if @loader.nil?
        @loader[key]
      rescue NoMethodError, TypeError
        logger.fatal 'rescue inside [](key)'
        nil
      end

      def set_prop(key, value)
        @loader = load if @loader.nil?
        @loader[key] = value
      end

      def merge_settings(key, hash)
        @loader = load if @loader.nil?
        thing = {}
        thing[key.to_sym] = hash
        @loader.load_module_settings(thing)
        schema.register(key.to_sym, hash)
        validate_module_on_merge(key.to_sym)
      end

      def define_schema(key, overrides)
        schema.define_override(key.to_sym, overrides)
      end

      def add_cross_validation(&block)
        cross_validations << block
      end

      def validate!
        @loader = load if @loader.nil?
        revalidate_all_modules
        run_cross_validations
        detect_unknown_keys
        raise ValidationError, errors unless errors.empty?
      end

      def schema
        @schema ||= Schema.new
      end

      def errors
        @loader = load if @loader.nil?
        @loader.errors
      end

      def logger
        @logger = if ::Legion.const_defined?('Logging')
                    ::Legion::Logging
                  else
                    require 'logger'
                    ::Logger.new($stdout)
                  end
      end

      private

      def cross_validations
        @cross_validations ||= []
      end

      def validate_module_on_merge(mod_name)
        values = @loader[mod_name]
        return unless values.is_a?(Hash)

        module_errors = schema.validate_module(mod_name, values)
        @loader.errors.concat(module_errors)
      end

      def revalidate_all_modules
        schema.registered_modules.each do |mod_name|
          values = @loader[mod_name]
          next unless values.is_a?(Hash)

          module_errors = schema.validate_module(mod_name, values)
          @loader.errors.concat(module_errors)
        end
        @loader.errors.uniq!
      end

      def run_cross_validations
        settings_hash = @loader.to_hash
        cross_validations.each do |block|
          block.call(settings_hash, @loader.errors)
        end
      end

      def detect_unknown_keys
        default_keys = @loader.default_settings.keys
        registered = schema.registered_modules
        known_defaults = default_keys - registered

        warnings = schema.detect_unknown_keys(@loader.to_hash, known_defaults: known_defaults)
        warnings.each do |w|
          @loader.errors << w
        end
      end
    end
  end
end
