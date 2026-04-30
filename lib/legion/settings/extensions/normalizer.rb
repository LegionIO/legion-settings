# frozen_string_literal: true

module Legion
  module Settings
    module Extensions
      # Normalizes tool, runner, and extension entries into canonical shapes
      # so every consumer sees the same fields regardless of the registration source.
      module Normalizer
        module_function

        # Canonical tool entry shape. Every field is present (possibly nil/empty).
        # Consumers can read entry[:input_schema] without defensive ||.
        #
        # Required by consumers:
        #   legion-llm ToolDefinition: name, description, input_schema, tool_class, extension, runner
        #   legion-llm dispatcher:     tool_class, extension, runner, function
        #   legion-llm executor:       tool_class, name, deferred
        #   legion-mcp ToolAdapter:    name, description, input_schema, tool_class
        #   legion-mcp server:         name
        #   legion-rbac:               extension, function
        def normalize_tool(name, metadata)
          {
            name:          name.to_s,
            description:   resolve_string(metadata, :description),
            input_schema:  resolve_schema(metadata),
            tool_class:    metadata[:tool_class],
            dispatch_type: resolve_dispatch_type(metadata),
            extension:     resolve_string(metadata, :extension),
            runner:        resolve_string(metadata, :runner),
            function:      resolve_string(metadata, :function),
            deferred:      metadata[:deferred] == true,
            sticky:        metadata.fetch(:sticky, true) == true,
            mcp_tier:      metadata[:mcp_tier],
            mcp_category:  resolve_string(metadata, :mcp_category),
            trigger_words: Array(metadata[:trigger_words]).map(&:to_s),
            tags:          Array(metadata[:tags]).map(&:to_s),
            source:        metadata.fetch(:source, :unknown).to_sym
          }
        end

        # Canonical runner entry shape.
        def normalize_runner(name, metadata)
          {
            name:          name.to_s,
            extension:     resolve_string(metadata, :extension),
            runner_module: resolve_string(metadata, :runner_module),
            function:      resolve_string(metadata, :function),
            exposed:       metadata.fetch(:exposed, true) == true,
            definition:    metadata[:definition]
          }
        end

        # Canonical extension entry shape.
        def normalize_extension(name, metadata)
          {
            name:       name.to_s,
            version:    resolve_string(metadata, :version),
            state:      metadata.fetch(:state, :discovered).to_sym,
            category:   metadata[:category],
            tier:       metadata[:tier],
            phase:      metadata[:phase],
            const_path: resolve_string(metadata, :const_path),
            runners:    Array(metadata[:runners])
          }
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

        def resolve_string(metadata, key)
          value = metadata[key]
          value&.to_s
        end
      end
    end
  end
end
