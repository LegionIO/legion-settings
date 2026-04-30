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
require 'legion/settings/extensions'

module Legion
  module Settings
    CORE_MODULES = %i[transport cache crypt data logging client region process].freeze

    class << self
      attr_accessor :loader

      include Legion::Logging::Helper

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
        load if @loader.nil?
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
        return nil if keys.empty?

        logger.info('Legion::Settings was not loaded, auto-loading now') if @loader.nil?
        load if @loader.nil?

        root = self[keys.first]
        return root if keys.length == 1
        return nil unless root.respond_to?(:dig)

        root.dig(*keys[1..])
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

      # Clean hook for legion-* core libraries to register their defaults.
      # Called at the bottom of the library's settings.rb file.
      # Library defaults fill in gaps; user JSON config wins.
      # Idempotent — calling twice with the same key is safe.
      #
      # Usage in legion-transport/lib/legion/transport/settings.rb:
      #   Legion::Settings.register_library(:transport, Legion::Transport::Settings.default)
      def register_library(key, defaults)
        sym = key.to_sym
        return if @registered_libraries&.include?(sym)

        merge_settings(sym, defaults)
        (@registered_libraries ||= []) << sym
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
      def load_project_env(start_dir: nil, loader: nil)
        target_loader = loader || ensure_loader
        path = ProjectEnv.load_into(target_loader.settings, start_dir: start_dir)
        target_loader.mark_dirty! if path
        path
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

      # ------------------------------------------------------------------
      # Hot-reload: re-read all previously loaded config files, re-resolve
      # vault:// / env:// / lease:// references, and notify registered
      # callbacks of changed keys.
      #
      # Safe to call from a SIGHUP handler or API endpoint.
      #
      # @return [Hash] changed keys  { key => { old: ..., new: ... } }
      # ------------------------------------------------------------------
      def reload!
        @reload_mutex ||= Mutex.new
        @reload_mutex.synchronize do
          return {} unless @loader

          old_hash = @loader.to_hash.dup
          files = @loader.loaded_files.dup

          # Re-create loader and replay the same files
          new_loader = Legion::Settings::Loader.new
          new_loader.load_env
          new_loader.load_dns_bootstrap
          files.each { |f| new_loader.load_file(f) if File.exist?(f) }

          # Replay module merges so extension defaults are preserved
          if @loader.respond_to?(:merged_modules)
            @loader.merged_modules.each do |mod_key, mod_defaults|
              new_loader.load_module_settings(mod_key => mod_defaults)
            end
          end

          # Replay project env overrides (.legionio.env)
          load_project_env(loader: new_loader)

          # Re-resolve secrets (vault://, env://, lease://)
          begin
            require 'legion/settings/resolver'
            Resolver.resolve_secrets!(new_loader.to_hash)
          rescue StandardError => e
            logger.warn("Settings reload: secret resolution failed: #{e.message}")
          end

          new_hash = new_loader.to_hash
          changes = diff_settings(old_hash, new_hash)

          if changes.empty?
            logger.info('Settings reload: no changes detected')
          else
            @loader = new_loader
            logger.info("Settings reload: #{changes.size} key(s) changed — #{changes.keys.join(', ')}")
            fire_reload_callbacks(changes)
          end

          changes
        end
      end

      # Register a SIGHUP handler that triggers reload!
      # Optionally accepts a block that will be called with the changes hash
      # after each successful reload.
      #
      # @yield [changes] optional callback receiving the changes hash
      def watch!(&block)
        on_reload(&block) if block

        unless Signal.list.key?('HUP')
          logger.info('Settings: SIGHUP not available on this platform — watch! is a no-op')
          return
        end

        # Single coalescing worker thread: SIGHUP sets the flag, worker drains it.
        @reload_flag ||= Queue.new
        @reload_worker ||= Thread.new do
          loop do
            @reload_flag.pop # blocks until signalled
            # Drain any queued signals so rapid SIGHUPs collapse into one reload
            @reload_flag.pop until @reload_flag.empty?
            logger.info('Settings: SIGHUP received — reloading configuration')
            reload!
          rescue StandardError => e
            logger.error("Settings: reload after SIGHUP failed: #{e.message}")
          end
        end

        trap('HUP') { @reload_flag << :reload }
        logger.info('Settings: SIGHUP handler registered for config hot-reload')
      end

      # Register a callback to be invoked after reload! detects changes.
      # Multiple callbacks can be registered; they are called in order.
      #
      # @yield [changes] the changes hash { key => { old: ..., new: ... } }
      def on_reload(&block)
        raise ArgumentError, 'on_reload requires a block' unless block

        @reload_callbacks ||= []
        @reload_callbacks << block
      end

      def reset!
        if @reload_worker&.alive? && @reload_worker != Thread.current
          @reload_worker.kill
          @reload_worker.join
        end

        @loader = nil
        @loaded = nil
        @schema = nil
        @cross_validations = nil
        @registered_libraries = nil
        @reload_callbacks = nil
        @reload_mutex = nil
        @reload_flag = nil
        @reload_worker = nil
        Overlay.clear_overlay!
      end

      def logger
        log
      end

      private

      def resolve_logger_settings
        raw_logging = @loader&.settings&.dig(:logging)
        raw_logging.is_a?(Hash) ? raw_logging : Legion::Logging::Settings.default
      end

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
        @loader.errors.clear
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

      def diff_settings(old_hash, new_hash, prefix = '')
        changes = {}
        all_keys = (old_hash.keys + new_hash.keys).uniq
        all_keys.each do |key|
          full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
          old_val = old_hash[key]
          new_val = new_hash[key]
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            changes.merge!(diff_settings(old_val, new_val, full_key))
          elsif old_val != new_val
            changes[full_key] = { old: old_val, new: new_val }
          end
        end
        changes
      end

      def fire_reload_callbacks(changes)
        return unless @reload_callbacks&.any?

        @reload_callbacks.each do |cb|
          cb.call(changes)
        rescue StandardError => e
          logger.warn("Settings reload callback failed: #{e.message}")
        end
      end
    end
  end
end
