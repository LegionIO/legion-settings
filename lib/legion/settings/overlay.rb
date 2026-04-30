# frozen_string_literal: true

require 'legion/settings/deep_merge'

module Legion
  module Settings
    # Thread-local request-scoped settings overlay.
    #
    # Provides block-scoped overrides that sit above global settings in the
    # resolution order: request overlay > project .legionio.env > global settings.
    #
    # Usage:
    #   Legion::Settings.with_overlay(llm: { default_model: 'claude-3-haiku' }) do
    #     Legion::Settings[:llm][:default_model]  # => 'claude-3-haiku'
    #   end
    #
    # Overlays are nestable — inner overlay merges on top of the outer one.
    module Overlay
      THREAD_KEY = :legion_settings_overlay

      class << self
        # Execute a block with the given overrides active in the current thread.
        # The overrides hash uses the same top-level key structure as Settings.
        #
        # @param overrides [Hash] settings to override for the duration of the block
        # @yield block executed with the overlay active
        # @return the return value of the block
        def with_overlay(overrides)
          previous = Thread.current[THREAD_KEY]
          Thread.current[THREAD_KEY] = deep_merge(previous || {}, overrides)
          yield
        ensure
          Thread.current[THREAD_KEY] = previous
        end

        # Return the current thread-local overlay hash, or nil if none is active.
        #
        # @return [Hash, nil]
        def current_overlay
          Thread.current[THREAD_KEY]
        end

        # Returns true when a thread-local overlay is active.
        #
        # @return [Boolean]
        def active?
          !Thread.current[THREAD_KEY].nil?
        end

        # Clear the thread-local overlay for the current thread.
        def clear_overlay!
          Thread.current[THREAD_KEY] = nil
        end

        # Resolve a top-level key against the active overlay, returning the
        # overlay value (which may need to be merged with base) or nil when no
        # overlay is set.
        #
        # @param key [Symbol, String]
        # @return [Object, nil]
        def overlay_for(key)
          overlay = Thread.current[THREAD_KEY]
          return nil unless overlay

          sym_key = key.to_sym
          str_key = key.to_s
          overlay[sym_key] || overlay[str_key]
        end

        private

        def deep_merge(base, overrides)
          DeepMerge.deep_merge(base, overrides)
        end
      end
    end
  end
end
