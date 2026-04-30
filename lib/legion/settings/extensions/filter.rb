# frozen_string_literal: true

module Legion
  module Settings
    module Extensions
      # Filter helpers for querying tools and extensions by criteria.
      module Filter
        module_function

        # Filter tool entries by criteria.
        #
        # Supported criteria:
        #   - extension: [String, Symbol] filter by extension name
        #   - deferred: [Boolean] filter by deferred flag
        #   - sticky: [Boolean] filter by sticky flag
        #   - mcp_tier: [Integer] filter by MCP tier
        #   - tags: [Array<String>] match any tag
        #   - category: [String, Symbol] filter by mcp_category
        #   - state: [Symbol] filter tools whose extension is in this state
        #   - source: [Symbol] filter by source (:discovery, :manual, :static)
        TOOL_EXACT_FILTERS = {
          deferred: :deferred, sticky: :sticky, mcp_tier: :mcp_tier, source: :source
        }.freeze

        TOOL_NORMALIZED_FILTERS = {
          extension: :extension, category: :mcp_category
        }.freeze

        def apply_tool_filters(entries, criteria, extension_store: nil)
          result = entries.dup
          apply_exact_tool_filters!(result, criteria)
          apply_normalized_tool_filters!(result, criteria)
          filter_by_tags!(result, criteria[:tags]) if criteria.key?(:tags)
          filter_by_extension_state!(result, criteria[:state], extension_store) if criteria.key?(:state) && extension_store
          result
        end

        def apply_exact_tool_filters!(result, criteria)
          TOOL_EXACT_FILTERS.each do |criteria_key, entry_key|
            next unless criteria.key?(criteria_key)

            value = criteria[criteria_key]
            result.select! { |t| t[entry_key] == value }
          end
        end

        def apply_normalized_tool_filters!(result, criteria)
          TOOL_NORMALIZED_FILTERS.each do |criteria_key, entry_key|
            next unless criteria.key?(criteria_key)

            value = normalize(criteria[criteria_key])
            result.select! { |t| normalize(t[entry_key]) == value }
          end
        end

        # Filter extension entries by criteria.
        #
        # Supported criteria:
        #   - state: [Symbol] filter by lifecycle state
        #   - data_required, cache_required, llm_required, etc.: [Boolean] filter by requirement flags
        #   - category: [String, Symbol] filter by category
        #   - phase: [Integer] filter by phase
        EXTENSION_BOOLEAN_FILTERS = %i[
          data_required cache_required transport_required crypt_required
          vault_required llm_required skills_required remote_invocable
          mcp_tools mcp_tools_deferred sticky_tools hot_reloadable
        ].freeze

        def apply_extension_filters(entries, criteria)
          result = entries.dup
          result.select! { |e| e[:state] == criteria[:state] } if criteria.key?(:state)
          result.select! { |e| normalize(e[:category]) == normalize(criteria[:category]) } if criteria.key?(:category)
          result.select! { |e| e[:phase] == criteria[:phase] } if criteria.key?(:phase)
          apply_extension_boolean_filters!(result, criteria)
          result
        end

        def apply_extension_boolean_filters!(result, criteria)
          EXTENSION_BOOLEAN_FILTERS.each do |key|
            next unless criteria.key?(key)

            result.select! { |e| e[key] == criteria[key] }
          end
        end

        def filter_by_tags!(result, tags)
          tags = Array(tags).map(&:to_s)
          result.select! { |t| Array(t[:tags]).map(&:to_s).intersect?(tags) }
        end

        def filter_by_extension_state!(result, state, extension_store)
          result.select! do |t|
            ext = extension_store.find(t[:extension])
            ext && ext[:state] == state
          end
        end

        def normalize(value)
          value.to_s
        end
      end
    end
  end
end
