# frozen_string_literal: true

require 'legion/json'
require 'legion/logging'
require 'legion/settings/version'
require 'legion/json/parse_error'
require 'legion/settings/loader'
require 'legion/settings/schema'
require 'legion/settings/validation_error'
require 'legion/settings/helper'
require 'legion/settings/overlay'
require 'legion/settings/project_env'

module Legion
  module Settings
    CORE_MODULES = %i[transport cache crypt data logging client region process].freeze

    class << self
      attr_accessor :loader

      def load(options = {})
        has_config = options[:config_file] || options[:config_dir] || options[:config_dirs]&.any?

        # Already fully loaded with config files — skip unless forced
        return @loader if @loaded && !options[:force]

        # Create Loader once; reuse for subsequent calls (preserves module merges)
        if @loader.nil? || options[:force]
          @loader = Legion::Settings::Loader.new
          @loader.load_env
          @loader.load_dns_bootstrap
        end

        @loader.load_file(options[:config_file]) if options[:config_file]
        @loader.load_directory(options[:config_dir]) if options[:config_dir]
        options[:config_dirs]&.each do |directory|
          @loader.load_directory(directory)
        end

        @loaded = true if has_config
        load_project_env
        logger.info("Settings loaded from #{@loader.loaded_files.size} files")
        @loader
      end

      def loaded?
        @loaded == true
      end

      def get(options = {})
        @loader || @loader = load(options)
      end

      def [](key)
        logger.info('Legion::Settings was not loaded, auto-loading now') if @loader.nil?
        ensure_loader
        overlay_val = Overlay.overlay_for(key)
        base_val = @loader[key]
        if overlay_val.is_a?(Hash) && base_val.is_a?(Hash)
          deep_merge_for_overlay(base_val, overlay_val)
        elsif !overlay_val.nil?
          overlay_val
        else
          base_val
        end
      rescue NoMethodError, TypeError => e
        logger.debug("Legion::Settings#[] key=#{key} failed: #{e.message}")
        nil
      end

      def dig(*keys)
        ensure_loader
        @loader.dig(*keys)
      rescue NoMethodError, TypeError => e
        logger.debug("Legion::Settings#dig keys=#{keys.inspect} failed: #{e.message}")
        nil
      end

      def set_prop(key, value)
        ensure_loader
        @loader[key] = value
      end

      def merge_settings(key, hash)
        ensure_loader
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

      # Execute a block with thread-local settings overrides active.
      # Overlays are nestable — inner overlays merge on top of outer ones.
      # Resolution order inside the block: overlay > project env > global settings.
      #
      # @param overrides [Hash] settings to override for the duration of the block
      # @yield the block executed with the overlay active
      # @return the return value of the block
      def with_overlay(overrides, &)
        Overlay.with_overlay(overrides, &)
      end

      # Load (or reload) the nearest `.legionio.env` file into the settings loader.
      # Searches from Dir.pwd upward.  Env-file values take priority over global
      # settings but are overridden by a request overlay (with_overlay).
      #
      # @param start_dir [String, nil] directory to start searching from (defaults to Dir.pwd)
      # @return [String, nil] path to the loaded file, or nil if none found
      def load_project_env(start_dir: nil)
        ensure_loader
        ProjectEnv.load_into(@loader.settings, start_dir: start_dir)
      end

      def dev_mode?
        return true if ENV['LEGION_DEV'] == 'true'

        Legion::Settings[:dev] ? true : false
      rescue StandardError => e
        logger.debug("Legion::Settings#dev_mode? failed: #{e.message}")
        false
      end

      def enterprise_privacy?
        return true if ENV['LEGION_ENTERPRISE_PRIVACY'] == 'true'

        Legion::Settings[:enterprise_data_privacy] ? true : false
      rescue StandardError => e
        logger.debug("Legion::Settings#enterprise_privacy? failed: #{e.message}")
        false
      end

      def validate!
        ensure_loader
        revalidate_all_modules
        run_cross_validations
        detect_unknown_keys
        if errors.empty?
          logger.info('Settings validation passed')
          return
        end

        unless dev_mode?
          logger.warn("Settings validation failed with #{errors.size} error(s)")
          raise ValidationError, errors
        end

        warn_validation_errors(errors)
      end

      def resolve_secrets!
        ensure_loader
        require 'legion/settings/resolver'
        Resolver.resolve_secrets!(@loader.to_hash)
        logger.debug('Secret resolution complete')
      end

      def schema
        @schema ||= Schema.new
      end

      def errors
        ensure_loader
        @loader.errors
      end

      def reset!
        @loader = nil
        @loaded = nil
        @schema = nil
        @cross_validations = nil
        Overlay.clear_overlay!
      end

      def logger
        @logger = if ::Legion.const_defined?('Logging')
                    ::Legion::Logging
                  else
                    require 'logger'
                    l = ::Logger.new($stdout)
                    l.formatter = proc do |severity, datetime, _progname, msg|
                      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S %z')}] #{severity} #{msg}\n"
                    end
                    l
                  end
      end

      private

      def deep_merge_for_overlay(base, overlay)
        result = base.dup
        overlay.each do |key, value|
          existing = result[key]
          result[key] = if existing.is_a?(Hash) && value.is_a?(Hash)
                          deep_merge_for_overlay(existing, value)
                        else
                          value
                        end
        end
        result
      end

      def ensure_loader
        return @loader if @loader

        @loader = Legion::Settings::Loader.new
        @loader.load_env
        logger.debug('Initialized Legion::Settings loader without config files')
        @loader
      end

      def cross_validations
        @cross_validations ||= []
      end

      def warn_validation_errors(errs)
        count = errs.length
        label = count == 1 ? 'error' : 'errors'
        message = "Legion::Settings dev mode: #{count} configuration #{label} detected (not raising):\n"
        message += errs.map { |e| "  [#{e[:module]}] #{e[:path]}: #{e[:message]}" }.join("\n")
        logger.warn(message)
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
