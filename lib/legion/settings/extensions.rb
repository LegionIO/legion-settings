# frozen_string_literal: true

require_relative 'extensions/store'
require_relative 'extensions/filter'
require_relative 'extensions/normalizer'

module Legion
  module Settings
    # Thread-safe runtime registry for extensions, runners, and tools.
    #
    # Used by the LegionIO boot pipeline to register discovered extensions,
    # their runner modules, and individual tools. Consumers (legion-mcp,
    # legion-llm, legion-rbac, API) read from this registry at runtime.
    #
    # Each store is a Concurrent::Map-backed Store instance. Read operations
    # return frozen duplicates so callers cannot mutate registry internals.
    module Extensions
      @extension_store = Store.new
      @runner_store = Store.new
      @tool_store = Store.new

      class << self
        # ----------------------------------------------------------------
        # Registration (called during LegionIO boot pipeline)
        # ----------------------------------------------------------------

        def register_extension(name, metadata = {})
          normalized = Normalizer.normalize_extension(name, metadata)
          @extension_store.register(name, normalized)
        end

        def register_runner(name, metadata = {})
          normalized = Normalizer.normalize_runner(name, metadata)
          @runner_store.register(name, normalized)
        end

        def register_tool(name, metadata = {})
          normalized = Normalizer.normalize_tool(name, metadata)
          @tool_store.register(name, normalized)
        end

        def transition(name, state, **extra)
          @extension_store.update(name, state: state, transitioned_at: Time.now, **extra)
        end

        # ----------------------------------------------------------------
        # Query (called by legion-mcp, legion-llm, legion-rbac, API)
        # ----------------------------------------------------------------

        def extensions
          @extension_store.all
        end

        def runners
          @runner_store.all
        end

        def tools
          @tool_store.all
        end

        def find_extension(name)
          @extension_store.find(name)
        end

        def find_runner(name)
          @runner_store.find(name)
        end

        def find_tool(name)
          @tool_store.find(name)
        end

        def filter_tools(**criteria)
          entries = @tool_store.all.map(&:dup)
          result = Filter.apply_tool_filters(entries, criteria, extension_store: @extension_store)
          result.each(&:freeze)
          result.freeze
        end

        def filter_extensions(**criteria)
          entries = @extension_store.all.map(&:dup)
          result = Filter.apply_extension_filters(entries, criteria)
          result.each(&:freeze)
          result.freeze
        end

        # ----------------------------------------------------------------
        # Lifecycle
        # ----------------------------------------------------------------

        def unregister_extension(name)
          removed = @extension_store.delete(name)
          return nil unless removed

          key = name.to_s
          @runner_store.delete_where { |v| v[:extension].to_s == key }
          @tool_store.delete_where { |v| v[:extension].to_s == key }
          removed
        end

        def unregister_tool(name)
          @tool_store.delete(name)
        end

        def reset!
          @extension_store.clear
          @runner_store.clear
          @tool_store.clear
        end

        # ----------------------------------------------------------------
        # Counts
        # ----------------------------------------------------------------

        def extension_count
          @extension_store.size
        end

        def runner_count
          @runner_store.size
        end

        def tool_count
          @tool_store.size
        end
      end
    end
  end
end
