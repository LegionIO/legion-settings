# frozen_string_literal: true

require 'concurrent/hash'

module Legion
  module Settings
    module Helper
      # Namespace boundary words — segment extraction stops at these.
      # Matches LegionIO's Extensions::Helpers::Base::NAMESPACE_BOUNDARIES.
      NAMESPACE_BOUNDARIES = %w[Actor Actors Runners Helpers Transport Data].freeze

      # Returns the gem-level settings hash for this extension.
      # Sub-modules (ConceptualBlending inside Agentic::Language) get
      # the SAME hash as the root — they access their section via key:
      #   settings[:conceptual_blending]
      #
      # Path resolution uses segments derived from the class namespace:
      #   Legion::Extensions::Github            → Settings[:extensions][:github]
      #   Legion::Extensions::Agentic::Learning → Settings[:extensions][:agentic][:learning]
      #   Legion::Extensions::MicrosoftTeams    → Settings[:extensions][:microsoft_teams]
      #   Legion::Extensions::Llm::Openai       → Settings[:extensions][:llm][:openai]
      def settings
        segments = derive_settings_segments
        dig_or_create(Legion::Settings[:extensions], segments)
      end

      private

      # Derives the gem-level segments from the class namespace.
      # Stops at NAMESPACE_BOUNDARIES so sub-modules (Runners, Actors, etc.)
      # resolve to their parent extension, not deeper.
      #
      # Legion::Extensions::Agentic::Learning::ConceptualBlending::Runners::Blend
      #   → ['agentic', 'learning'] (stops at ConceptualBlending because next is Runners)
      #
      # Legion::Extensions::Agentic::Learning::ConceptualBlending
      #   → ['agentic', 'learning'] (stops at ConceptualBlending — it's a sub-module, not a segment)
      #
      # Wait — ConceptualBlending IS a namespace part, not a boundary word.
      # The gem is lex-agentic-learning → segments are ['agentic', 'learning'].
      # ConceptualBlending is INSIDE the gem, not part of the gem name.
      # So we need to know the gem's segment count to stop there.
      #
      # Strategy: if the caller responds to :segments (LegionIO's Base mixin),
      # use those directly. Otherwise derive from namespace, stopping at
      # boundary words or after 2 levels (covers most lex-X-Y patterns).
      def derive_settings_segments
        # Prefer explicit segments from LegionIO's Helpers::Base
        return segments.map { |s| s.to_s.to_sym } if respond_to?(:segments)

        derive_segments_from_class
      end

      def derive_segments_from_class
        name = respond_to?(:ancestors) ? ancestors.first.to_s : self.class.to_s
        parts = name.split('::')
        ext_idx = parts.index('Extensions')
        return [camelize_to_snake(parts.last).to_sym] unless ext_idx

        segment_parts = []
        ((ext_idx + 1)...parts.length).each do |i|
          break if NAMESPACE_BOUNDARIES.include?(parts[i])

          segment_parts << camelize_to_snake(parts[i]).to_sym
        end

        # The gem-level segments are the parts between Extensions:: and
        # the first sub-module that isn't part of the gem name.
        # For lex-agentic-learning, gem segments = [:agentic, :learning].
        # ConceptualBlending is a sub-module INSIDE the gem.
        # We use the registered extension entry to find the correct depth,
        # falling back to all segments if no registry entry exists.
        resolve_gem_segments(segment_parts)
      end

      def resolve_gem_segments(all_segments)
        return all_segments if all_segments.length <= 1

        # Check if Settings::Extensions has this extension registered
        # with known segments — use those as the authoritative gem boundary.
        if defined?(Legion::Settings::Extensions)
          # Try progressively shorter segment paths to find the registered gem
          all_segments.length.downto(1) do |len|
            candidate = all_segments[0, len]
            gem_name = "lex-#{candidate.join('-')}"
            entry = Legion::Settings::Extensions.find_extension(gem_name)
            return candidate if entry
          end
        end

        all_segments
      end

      # Digs into a nested hash using segments as keys, creating
      # Concurrent::Hash at each level if missing.
      def dig_or_create(root, segments)
        return Concurrent::Hash.new unless root.is_a?(Hash)

        segments.reduce(root) do |current, key|
          if current.is_a?(Hash) && current.key?(key)
            current[key]
          elsif current.is_a?(Hash)
            empty = Concurrent::Hash.new
            current[key] = empty
            empty
          else
            return Concurrent::Hash.new
          end
        end
      end

      def camelize_to_snake(str)
        str.to_s
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
      end
    end
  end
end
