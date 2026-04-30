# frozen_string_literal: true

module Legion
  module Settings
    module Extensions
      # Normalizes tool, runner, and extension entries into complete, known schemas.
      #
      # This is the single source of truth for what fields exist on each entry type.
      # Every field that ANY consumer reads is defined here. Consumers can access
      # any field without defensive nil-checks — absent values are explicitly nil,
      # empty arrays, or empty hashes.
      #
      # If a new consumer needs a field, add it here — don't rely on passthrough.
      module Normalizer
        module_function

        # -------------------------------------------------------------------
        # Tool: generated from an exposed runner function or hand-authored
        # -------------------------------------------------------------------
        #
        # Consumers:
        #   legion-llm: ToolDefinition wire format, executor tool loop, dispatcher
        #   legion-mcp: ToolAdapter, server registration, deferred registry
        #   legion-rbac: access control by extension/function
        #   LegionIO API: tool listing, diagnostics
        def normalize_tool(name, metadata)
          {
            # Identity
            name:          name.to_s,
            description:   resolve_string(metadata, :description),
            input_schema:  resolve_schema(metadata),

            # Execution
            tool_class:    metadata[:tool_class],
            dispatch_type: resolve_dispatch_type(metadata),

            # Back-references to owning extension/runner/function
            extension:     resolve_string(metadata, :extension) || resolve_string(metadata, :ext_name),
            runner:        resolve_string(metadata, :runner) || resolve_string(metadata, :runner_snake),
            function:      resolve_string(metadata, :function),

            # Classification
            deferred:      metadata[:deferred] == true,
            sticky:        metadata.fetch(:sticky, true) == true,
            mcp_tier:      metadata[:mcp_tier],
            mcp_category:  resolve_string(metadata, :mcp_category),
            trigger_words: Array(metadata[:trigger_words]).map(&:to_s),
            tags:          Array(metadata[:tags]).map(&:to_s),
            source:        metadata.fetch(:source, :unknown).to_sym,

            # Confidence / override tracking (written by Tools::Confidence)
            confidence:    metadata[:confidence],
            hit_count:     metadata[:hit_count],
            miss_count:    metadata[:miss_count]
          }
        end

        # -------------------------------------------------------------------
        # Runner: a module on an extension that exposes callable functions
        # -------------------------------------------------------------------
        #
        # Consumers:
        #   LegionIO Tools::Discovery: function synthesis, schema building
        #   legion-mcp runner_catalog: runner listing
        #   legion-mcp FunctionDiscovery: tool building from runner methods
        def normalize_runner(name, metadata)
          {
            # Identity
            name:          name.to_s,
            extension:     resolve_string(metadata, :extension),
            runner_module: resolve_string(metadata, :runner_module),

            # Functions exposed by this runner
            function:      resolve_string(metadata, :function),
            functions:     metadata[:functions] || metadata[:class_methods] || {},
            exposed:       metadata.fetch(:exposed, true) == true,
            definition:    metadata[:definition],

            # MCP/tool behavior inherited by functions on this runner
            mcp_tools:     metadata[:mcp_tools],
            mcp_deferred:  metadata[:mcp_deferred],
            trigger_words: Array(metadata[:trigger_words]).map(&:to_s)
          }
        end

        # -------------------------------------------------------------------
        # Extension: a loaded LEX gem with runners, actors, and tools
        # -------------------------------------------------------------------
        #
        # Consumers:
        #   LegionIO boot pipeline: phased loading, lifecycle management
        #   LegionIO HandleRegistry: state tracking, hot reload
        #   LegionIO Registry::Governance: approval, risk tier, naming
        #   LegionIO Registry::SecurityScanner: checksum, static analysis
        #   LegionIO Catalog::Available: static listing
        #   LegionIO API: extension listing, diagnostics
        #   legion-mcp: extension_info resource
        #   legion-llm: extension filter in tool queries
        def normalize_extension(name, metadata) # rubocop:disable Metrics/AbcSize
          segments = resolve_segments(name, metadata)
          {
            # Identity (derived from gem name via Helpers::Segments conventions)
            name:                     name.to_s,
            gem_name:                 resolve_string(metadata, :gem_name) || name.to_s,
            description:              resolve_string(metadata, :description),
            version:                  resolve_string(metadata, :version),
            const_path:               resolve_string(metadata, :const_path),
            segments:                 segments,
            lex_name:                 resolve_string(metadata, :lex_name) || segments.join('_'),
            lex_slug:                 resolve_string(metadata, :lex_slug) || segments.join('.'),
            amqp_prefix:              resolve_string(metadata, :amqp_prefix),
            settings_path:            resolve_string(metadata, :settings_path),
            table_prefix:             resolve_string(metadata, :table_prefix),

            # Lifecycle state
            state:                    metadata.fetch(:state, :discovered).to_sym,
            loaded_at:                metadata[:loaded_at],
            last_error:               metadata[:last_error],

            # Boot classification
            category:                 metadata[:category],
            tier:                     metadata[:tier],
            phase:                    metadata[:phase],

            # Requirement flags — queryable WITHOUT loading the extension module.
            # LegionIO boot checks these to skip extensions whose deps aren't ready.
            # Defaults match Core module defaults so unset flags behave identically.
            data_required:            metadata.fetch(:data_required, false) == true,
            cache_required:           metadata.fetch(:cache_required, false) == true,
            transport_required:       metadata.fetch(:transport_required, true) == true,
            crypt_required:           metadata.fetch(:crypt_required, false) == true,
            vault_required:           metadata.fetch(:vault_required, false) == true,
            llm_required:             metadata.fetch(:llm_required, false) == true,
            skills_required:          metadata.fetch(:skills_required, false) == true,
            remote_invocable:         metadata.fetch(:remote_invocable, true) == true,

            # Extension contents
            runners:                  Array(metadata[:runners]),
            actors:                   Array(metadata[:actors]),
            tools:                    Array(metadata[:tools]),
            absorbers:                Array(metadata[:absorbers]),
            routes:                   Array(metadata[:routes]),

            # Gem metadata
            spec:                     metadata[:spec],
            gem_dir:                  resolve_string(metadata, :gem_dir),
            active_version:           resolve_string(metadata, :active_version),
            latest_installed_version: resolve_string(metadata, :latest_installed_version),
            loaded_features:          Array(metadata[:loaded_features]),

            # Reload support
            reload_state:             metadata.fetch(:reload_state, :idle),
            hot_reloadable:           metadata[:hot_reloadable] == true,

            # Governance / security
            author:                   resolve_string(metadata, :author),
            risk_tier:                resolve_string(metadata, :risk_tier),
            airb_status:              resolve_string(metadata, :airb_status),
            permissions:              Array(metadata[:permissions]),
            checksum:                 resolve_string(metadata, :checksum),

            # Tool behavior defaults
            mcp_tools:                metadata.fetch(:mcp_tools, true) == true,
            mcp_tools_deferred:       metadata.fetch(:mcp_tools_deferred, true) == true,
            sticky_tools:             metadata.fetch(:sticky_tools, true) == true,

            # Extension settings — the complete declared configuration with
            # effective runtime values (defaults merged with user overrides).
            # Enables introspection: "what can I configure?" and "what's the
            # current value?" without loading the extension module.
            # Populated by LegionIO from default_settings merged with
            # Legion::Settings[:extensions][:lex_name] at registration time.
            settings_schema:          metadata[:settings_schema] || {},
            settings:                 metadata[:settings] || {}
          }
        end

        # -------------------------------------------------------------------
        # Schema resolution
        # -------------------------------------------------------------------

        def resolve_schema(metadata)
          schema = metadata[:input_schema] || metadata[:parameters] || metadata[:params_schema]
          schema.is_a?(Hash) ? schema : {}
        end

        # -------------------------------------------------------------------
        # Dispatch type detection
        # -------------------------------------------------------------------

        def resolve_dispatch_type(metadata)
          return metadata[:dispatch_type].to_sym if metadata[:dispatch_type]

          tool_class = metadata[:tool_class]
          return :runner if tool_class.nil? && metadata[:extension] && metadata[:function]
          return :none unless tool_class

          if tool_class.respond_to?(:new) && tool_class.method_defined?(:execute)
            :instance
          elsif tool_class.respond_to?(:call)
            :class_call
          else
            :none
          end
        end

        def resolve_string(metadata, key)
          value = metadata[key]
          value&.to_s
        end

        # Derive segments from the published gem name. No magic, no lookup tables.
        #
        # Rules (matching Ruby gem → module conventions):
        #   dash '-'       = module boundary:   lex-agentic-learning → ['agentic', 'learning'] → Agentic::Learning
        #   underscore '_' = CamelCase inside:  lex-microsoft_teams  → ['microsoft_teams']     → MicrosoftTeams
        #
        # Examples:
        #   lex-github              → ['github']                       → Legion::Extensions::Github
        #   lex-agentic-learning    → ['agentic', 'learning']          → Legion::Extensions::Agentic::Learning
        #   lex-llm-openai          → ['llm', 'openai']               → Legion::Extensions::Llm::Openai
        #   lex-llm-azure-foundry   → ['llm', 'azure', 'foundry']     → Legion::Extensions::Llm::Azure::Foundry
        #   lex-llm-azure_foundry   → ['llm', 'azure_foundry']        → Legion::Extensions::Llm::AzureFoundry
        #   lex-microsoft_teams     → ['microsoft_teams']              → Legion::Extensions::MicrosoftTeams
        def resolve_segments(name, metadata)
          return Array(metadata[:segments]) if metadata[:segments]&.any?

          gem = (metadata[:gem_name] || name).to_s
          base = gem.start_with?('lex-') ? gem.sub(/\Alex-/, '') : gem
          base.split('-')
        end
      end
    end
  end
end
