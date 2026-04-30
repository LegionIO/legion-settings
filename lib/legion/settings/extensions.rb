# frozen_string_literal: true

require 'concurrent/map'

module Legion
  module Settings
    # Thread-safe runtime registry for extensions, runners, and tools.
    #
    # Used by the LegionIO boot pipeline to register discovered extensions,
    # their runner modules, and individual tools. Consumers (legion-mcp,
    # legion-llm, legion-rbac, API) read from this registry at runtime.
    #
    # All three stores use Concurrent::Map which provides thread-safe
    # reads and writes without explicit locking. Read operations return
    # frozen duplicates so callers cannot mutate the registry internals.
    module Extensions
      @extensions = Concurrent::Map.new
      @runners = Concurrent::Map.new
      @tools = Concurrent::Map.new

      class << self
        # ----------------------------------------------------------------
        # Registration (called during LegionIO boot pipeline)
        # ----------------------------------------------------------------

        # Register an extension (gem discovered/loaded).
        #
        # @param name [String, Symbol] extension name (e.g. 'lex-ollama')
        # @param metadata [Hash] extension metadata (state, category, tier, phase, etc.)
        # @return [Hash] frozen copy of the registered entry
        def register_extension(name, metadata = {})
          key = normalize_key(name)
          entry = { name: key, registered_at: Time.now }.merge(metadata)
          @extensions[key] = entry
          entry.freeze
        end

        # Register a runner module discovered from an extension.
        #
        # @param name [String, Symbol] runner name (e.g. 'ollama/inference/chat')
        # @param metadata [Hash] runner metadata (extension, runner_module, function, etc.)
        # @return [Hash] frozen copy of the registered entry
        def register_runner(name, metadata = {})
          key = normalize_key(name)
          entry = { name: key, registered_at: Time.now }.merge(metadata)
          @runners[key] = entry
          entry.freeze
        end

        # Register a tool discovered from a runner.
        #
        # @param name [String, Symbol] tool name (e.g. 'legion.ollama_inference_chat')
        # @param metadata [Hash] tool metadata (extension, runner, function, deferred, etc.)
        # @return [Hash] frozen copy of the registered entry
        def register_tool(name, metadata = {})
          key = normalize_key(name)
          entry = { name: key, registered_at: Time.now }.merge(metadata)
          @tools[key] = entry
          entry.freeze
        end

        # Transition an extension to a new lifecycle state.
        #
        # @param name [String, Symbol] extension name
        # @param state [Symbol] new state (:discovered, :loaded, :running, :stopped)
        # @param extra [Hash] additional metadata to merge (e.g. runners list on :loaded)
        # @return [Hash, nil] frozen copy of the updated entry, or nil if not found
        def transition(name, state, **extra)
          key = normalize_key(name)
          updated = nil
          @extensions.compute(key) do |old_entry|
            if old_entry
              updated = old_entry.dup.merge({ state: state, transitioned_at: Time.now }.merge(extra))
              updated
            end
          end
          updated&.freeze
        end

        # ----------------------------------------------------------------
        # Query (called by legion-mcp, legion-llm, legion-rbac, API)
        # ----------------------------------------------------------------

        # All registered extensions.
        #
        # @return [Array<Hash>] frozen array of frozen extension hashes
        def extensions
          snapshot = @extensions.values.map(&:dup)
          snapshot.each(&:freeze)
          snapshot.freeze
        end

        # All registered runners.
        #
        # @return [Array<Hash>] frozen array of frozen runner hashes
        def runners
          snapshot = @runners.values.map(&:dup)
          snapshot.each(&:freeze)
          snapshot.freeze
        end

        # All registered tools.
        #
        # @return [Array<Hash>] frozen array of frozen tool hashes
        def tools
          snapshot = @tools.values.map(&:dup)
          snapshot.each(&:freeze)
          snapshot.freeze
        end

        # Find a single extension by name.
        #
        # @param name [String, Symbol] extension name
        # @return [Hash, nil] frozen copy of the extension entry, or nil
        def find_extension(name)
          key = normalize_key(name)
          @extensions[key]&.dup&.freeze
        end

        # Find a single runner by name.
        #
        # @param name [String, Symbol] runner name
        # @return [Hash, nil] frozen copy of the runner entry, or nil
        def find_runner(name)
          key = normalize_key(name)
          @runners[key]&.dup&.freeze
        end

        # Find a single tool by name.
        #
        # @param name [String, Symbol] tool name
        # @return [Hash, nil] frozen copy of the tool entry, or nil
        def find_tool(name)
          key = normalize_key(name)
          @tools[key]&.dup&.freeze
        end

        # Filter tools by criteria.
        #
        # @param criteria [Hash] filter options:
        #   - extension: [String, Symbol] filter by extension name
        #   - deferred: [Boolean] filter by deferred flag
        #   - sticky: [Boolean] filter by sticky flag
        #   - mcp_tier: [Integer] filter by MCP tier
        #   - tags: [Array<String>] match any tag
        #   - category: [String, Symbol] filter by mcp_category
        #   - state: [Symbol] filter tools whose extension is in this state
        #   - source: [Symbol] filter by source (:discovery, :manual, :static)
        # @return [Array<Hash>] frozen array of frozen matching tool hashes
        def filter_tools(**criteria)
          result = @tools.values.map(&:dup)
          result = apply_tool_filters(result, criteria)
          result.each(&:freeze)
          result.freeze
        end

        # Filter extensions by criteria.
        #
        # @param criteria [Hash] filter options:
        #   - state: [Symbol] filter by state
        #   - category: [String, Symbol] filter by category
        #   - phase: [Integer] filter by phase
        # @return [Array<Hash>] frozen array of frozen matching extension hashes
        def filter_extensions(**criteria)
          result = @extensions.values.map(&:dup)
          result = apply_extension_filters(result, criteria)
          result.each(&:freeze)
          result.freeze
        end

        # ----------------------------------------------------------------
        # Lifecycle
        # ----------------------------------------------------------------

        # Unregister an extension and cascade-remove its runners and tools.
        #
        # @param name [String, Symbol] extension name
        # @return [Hash, nil] the removed extension entry, or nil if not found
        def unregister_extension(name)
          key = normalize_key(name)
          removed = @extensions.delete(key)
          return nil unless removed

          @runners.each_pair { |k, v| @runners.delete(k) if normalize_key(v[:extension]) == key }
          @tools.each_pair { |k, v| @tools.delete(k) if normalize_key(v[:extension]) == key }
          removed
        end

        # Unregister a single tool.
        #
        # @param name [String, Symbol] tool name
        # @return [Hash, nil] the removed tool entry, or nil if not found
        def unregister_tool(name)
          key = normalize_key(name)
          @tools.delete(key)
        end

        # Clear all registries. Intended for test cleanup.
        #
        # @return [void]
        def reset!
          @extensions.clear
          @runners.clear
          @tools.clear
        end

        # ----------------------------------------------------------------
        # Counts (convenience)
        # ----------------------------------------------------------------

        # @return [Integer] number of registered extensions
        def extension_count
          @extensions.size
        end

        # @return [Integer] number of registered runners
        def runner_count
          @runners.size
        end

        # @return [Integer] number of registered tools
        def tool_count
          @tools.size
        end

        private

        def normalize_key(name)
          name.to_s
        end

        def apply_tool_filters(result, criteria)
          result.select! { |t| normalize_key(t[:extension]) == normalize_key(criteria[:extension]) } if criteria.key?(:extension)
          result.select! { |t| t[:deferred] == criteria[:deferred] } if criteria.key?(:deferred)
          result.select! { |t| t[:sticky] == criteria[:sticky] } if criteria.key?(:sticky)
          result.select! { |t| t[:mcp_tier] == criteria[:mcp_tier] } if criteria.key?(:mcp_tier)
          result.select! { |t| normalize_key(t[:mcp_category]) == normalize_key(criteria[:category]) } if criteria.key?(:category)
          result.select! { |t| t[:source] == criteria[:source] } if criteria.key?(:source)
          filter_by_tags!(result, criteria[:tags]) if criteria.key?(:tags)
          filter_by_extension_state!(result, criteria[:state]) if criteria.key?(:state)
          result
        end

        def filter_by_tags!(result, tags)
          tags = Array(tags).map(&:to_s)
          result.select! { |t| Array(t[:tags]).map(&:to_s).intersect?(tags) }
        end

        def filter_by_extension_state!(result, state)
          result.select! do |t|
            ext = @extensions[normalize_key(t[:extension])]
            ext && ext[:state] == state
          end
        end

        def apply_extension_filters(result, criteria)
          result.select! { |e| e[:state] == criteria[:state] } if criteria.key?(:state)
          result.select! { |e| normalize_key(e[:category]) == normalize_key(criteria[:category]) } if criteria.key?(:category)
          result.select! { |e| e[:phase] == criteria[:phase] } if criteria.key?(:phase)
          result
        end
      end
    end
  end
end
