# frozen_string_literal: true

module Legion
  module Settings
    module Extensions
      # Normalizes tool, runner, and extension entries into canonical shapes
      # so every consumer sees the same fields regardless of the registration source.
      #
      # Extra fields not in the canonical shape are preserved in the output —
      # the normalizer guarantees canonical fields exist but does not strip
      # caller-supplied metadata that consumers like HandleRegistry, Governance,
      # or SecurityScanner may need.
      module Normalizer
        module_function

        # Canonical tool entry shape. Every canonical field is present (possibly nil/empty).
        # Extra fields from metadata are merged in after canonical fields.
        def normalize_tool(name, metadata)
          canonical = {
            name:          name.to_s,
            description:   resolve_string(metadata, :description),
            input_schema:  resolve_schema(metadata),
            tool_class:    metadata[:tool_class],
            dispatch_type: resolve_dispatch_type(metadata),
            extension:     resolve_tool_extension(metadata),
            runner:        resolve_tool_runner(metadata),
            function:      resolve_string(metadata, :function),
            deferred:      metadata[:deferred] == true,
            sticky:        metadata.fetch(:sticky, true) == true,
            mcp_tier:      metadata[:mcp_tier],
            mcp_category:  resolve_string(metadata, :mcp_category),
            trigger_words: Array(metadata[:trigger_words]).map(&:to_s),
            tags:          Array(metadata[:tags]).map(&:to_s),
            source:        metadata.fetch(:source, :unknown).to_sym
          }
          merge_extra(metadata, canonical)
        end

        # Canonical runner entry shape. Extra fields preserved.
        def normalize_runner(name, metadata)
          canonical = {
            name:          name.to_s,
            extension:     resolve_string(metadata, :extension),
            runner_module: resolve_string(metadata, :runner_module),
            function:      resolve_string(metadata, :function),
            exposed:       metadata.fetch(:exposed, true) == true,
            definition:    metadata[:definition]
          }
          merge_extra(metadata, canonical)
        end

        # Canonical extension entry shape. Extra fields preserved.
        # HandleRegistry, Governance, and SecurityScanner pass fields like
        # gem_name, spec, gem_dir, risk_tier, etc. that are NOT canonical
        # but must survive registration.
        def normalize_extension(name, metadata)
          canonical = {
            name:        name.to_s,
            description: resolve_string(metadata, :description),
            version:     resolve_string(metadata, :version),
            state:       metadata.fetch(:state, :discovered).to_sym,
            category:    metadata[:category],
            tier:        metadata[:tier],
            phase:       metadata[:phase],
            const_path:  resolve_string(metadata, :const_path),
            runners:     Array(metadata[:runners])
          }
          merge_extra(metadata, canonical)
        end

        # Resolves input_schema from whichever key the caller used.
        # Discovery uses :input_schema, lex-llm tools use :parameters or #params_schema.
        def resolve_schema(metadata)
          schema = metadata[:input_schema] || metadata[:parameters] || metadata[:params_schema]
          schema.is_a?(Hash) ? schema : {}
        end

        # Determines how the tool should be called:
        #   :class_call  — tool_class.call(**args) → { content: [...] }
        #   :instance    — tool_class.new.call(args) → String
        #   :runner      — dispatch through extension runner via Ingress
        #   :none        — metadata only, not executable server-side
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

        # Discovery uses :ext_name, canonical uses :extension.
        def resolve_tool_extension(metadata)
          resolve_string(metadata, :extension) || resolve_string(metadata, :ext_name)
        end

        # Discovery uses :runner_snake, canonical uses :runner.
        def resolve_tool_runner(metadata)
          resolve_string(metadata, :runner) || resolve_string(metadata, :runner_snake)
        end

        def resolve_string(metadata, key)
          value = metadata[key]
          value&.to_s
        end

        # Merges extra fields from metadata that are not in the canonical set.
        # Canonical fields always win — extra fields fill in around them.
        def merge_extra(metadata, canonical)
          extra = metadata.reject { |k, _| canonical.key?(k) || internal_alias?(k) }
          canonical.merge(extra)
        end

        # Keys that are aliases resolved into canonical fields — don't duplicate them.
        def internal_alias?(key)
          %i[ext_name runner_snake parameters params_schema].include?(key)
        end
      end
    end
  end
end
