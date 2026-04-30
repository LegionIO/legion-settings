# frozen_string_literal: true

require 'concurrent/hash'

module Legion
  module Settings
    # Shared deep-merge logic used by Loader, Overlay, ProjectEnv, and
    # the top-level Settings module.  Consolidates four previously
    # duplicated implementations into one place.
    module DeepMerge
      module_function

      # Non-destructive deep merge.  Returns a new hash with +override+
      # values merged on top of +base+.  Preserves Concurrent::Hash type
      # when the base hash is one.
      #
      # @param base     [Hash] the base hash
      # @param override [Hash] values to merge on top
      # @return [Hash]
      def deep_merge(base, override)
        merged = base.is_a?(Concurrent::Hash) ? Concurrent::Hash[base] : base.dup
        override.each do |key, value|
          existing = base[key]
          merged[key] = if existing.is_a?(Hash) && value.is_a?(Hash)
                          deep_merge(existing, value)
                        elsif existing.is_a?(Array) && value.is_a?(Array)
                          (existing + value).uniq
                        else
                          value
                        end
        end
        merged
      end

      # In-place deep merge.  Mutates +base+ with values from +override+.
      # Nested hashes are merged recursively; scalars and arrays are replaced.
      #
      # @param base     [Hash] the hash to mutate
      # @param override [Hash] values to merge in
      # @return [Hash] the mutated base hash
      def deep_merge!(base, override)
        override.each do |key, value|
          if base[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge!(base[key], value)
          else
            base[key] = value
          end
        end
        base
      end
    end
  end
end
