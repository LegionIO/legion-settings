# frozen_string_literal: true

require 'legion/logging'
require 'weakref'

module Legion
  module Settings
    module Resolver
      extend Legion::Logging::Helper

      # The delimiter follows a nonempty path/name; subsequent path characters cannot consume it.
      VAULT_PATTERN  = %r{\Avault://([^\n][^#\n]*)#([^\n]+)\z}
      ENV_PATTERN    = %r{\Aenv://(.+)\z}
      LEASE_PATTERN  = %r{\Alease://([^\n][^#\n]*)#([^\n]+)\z}
      URI_PATTERN    = %r{\A(?:vault|env|lease)://}

      @source_mutex = Mutex.new
      @source_states = {}

      module_function

      def resolve_secrets!(settings_hash, owner: settings_hash, previous_owner: nil, strict: false, publish: nil)
        return settings_hash unless settings_hash.is_a?(Hash)

        state = resolution_state(owner: owner)
        previous = previous_owner ? resolution_state(owner: previous_owner) : state
        state[:mutex].synchronize do
          context = { vault_available: vault_connected?, vault_cache: {}, sources: state[:sources], strict: strict }
          prefetch_vault(value: settings_hash, context: context)
          state[:sources].each_value { |record| prefetch_vault(value: record[:source], context: context) }
          publication = lambda do |proposal|
            publish&.call(proposal)
            state[:sources] = proposal[:sources]
          end
          preparation = lambda do |lease_reader|
            context[:lease_reader] = lease_reader
            proposal = { paths: previous[:sources].filter_map { |path, record| path if record[:lease] },
                         assignments: [], references: [], sources: {}, resolved: 0, unresolved: 0 }
            walk(settings_hash, path: [], context: context, proposal: proposal)
            proposal[:paths].uniq!
            proposal
          end

          needs_leases = lease_sources?(settings: settings_hash, sources: state[:sources], previous_sources: previous[:sources])
          proposal = if needs_leases && lease_manager_available?
                       manager = Legion::Crypt::LeaseManager.instance
                       unless manager.respond_to?(:update_settings_refs)
                         raise 'Lease resolution requires legion-crypt >= 1.5.38 for atomic settings reference replacement'
                       end

                       manager.update_settings_refs(settings: settings_hash, publish: publication, &preparation)
                     else
                       apply_resolution(proposal: preparation.call(nil), publish: publication)
                     end
          if proposal[:resolved].positive? || proposal[:unresolved].positive?
            log.info("Settings resolver: #{proposal[:resolved]} resolved, #{proposal[:unresolved]} unresolved")
          end
        end
        settings_hash
      end

      # Strong state values keep provenance alive across GC; weak owner references
      # avoid retaining retired loaders and never alter Hash serialization or dup.
      def resolution_state(owner:)
        @source_mutex.synchronize do
          @source_states.delete_if { |_id, state| !state[:owner].weakref_alive? }
          # Identity keys must not retain owners; compare_by_identity would hold them strongly.
          @source_states[owner.object_id] ||= { owner: WeakRef.new(owner), mutex: Mutex.new, sources: {} } # rubocop:disable Lint/HashCompareByIdentity
        end
      end

      def lease_sources?(settings:, sources:, previous_sources:)
        count_lease_refs(settings).positive? ||
          sources.any? { |_path, record| count_lease_refs(record[:source]).positive? } ||
          previous_sources.any? { |_path, record| record[:lease] }
      end

      def resolve_value(value, context: nil)
        case value
        when String
          return value unless value.match?(URI_PATTERN)

          resolve_single(value, context: context)
        when Array
          return value unless resolvable_chain?(value)

          resolve_chain(value, context: context)
        else
          value
        end
      end

      def resolve_single(str, context: nil)
        if (match = str.match(VAULT_PATTERN))
          resolve_vault(match[1], match[2], context: context)
        elsif (match = str.match(LEASE_PATTERN))
          resolve_lease(match[1], match[2], context: context)
        elsif (match = str.match(ENV_PATTERN))
          ENV.fetch(match[1], nil)
        else
          str
        end
      end

      def resolve_chain(arr, context: nil)
        context ||= { vault_available: vault_connected?, vault_cache: {} }
        arr.each do |entry|
          result = if entry.is_a?(String) && entry.match?(URI_PATTERN)
                     resolve_single(entry, context: context)
                   else
                     entry
                   end
          next if result.nil?

          yield(entry) if block_given?
          return result
        end
        nil
      end

      def has_vault_refs?(hash) # rubocop:disable Naming/PredicatePrefix
        count_vault_refs(hash).positive?
      end

      def count_vault_refs(hash)
        case hash
        when String then hash.match?(VAULT_PATTERN) ? 1 : 0
        when Array  then hash.sum { |value| count_vault_refs(value) }
        when Hash   then hash.sum { |_key, value| count_vault_refs(value) }
        else 0
        end
      end

      def vault_connected?
        return false unless defined?(Legion::Crypt)
        return Legion::Crypt.vault_connected? if Legion::Crypt.respond_to?(:vault_connected?)

        Legion::Settings[:crypt]&.dig(:vault, :connected) == true ||
          (Legion::Crypt.respond_to?(:connected_clusters) && Legion::Crypt.connected_clusters.any?)
      rescue StandardError => e
        log.debug("Legion::Settings::Resolver#vault_connected? failed: #{e.message}")
        false
      end

      def walk(container, path:, context:, proposal:)
        keys = container.is_a?(Hash) ? container.each_key : container.each_index
        keys.each do |key|
          current_path = (path + [key]).freeze
          next if prepare_value(container: container, key: key, path: current_path, context: context, proposal: proposal)

          value = container[key]
          walk(value, path: current_path, context: context, proposal: proposal) if value.is_a?(Hash) || value.is_a?(Array)
        end
      end

      def source_declaration(value:, record:)
        if declaration?(value: value)
          return value.dup.freeze unless value.is_a?(Array)

          value.map { |entry| entry.is_a?(String) ? entry.dup.freeze : entry }.freeze
        elsif record && value == record[:value]
          record[:source]
        end
      end

      def declaration?(value:)
        (value.is_a?(String) && value.match?(URI_PATTERN)) ||
          (value.is_a?(Array) && resolvable_chain?(value) && value.none? { |entry| entry.is_a?(Hash) || entry.is_a?(Array) })
      end

      def prepare_value(container:, key:, path:, context:, proposal:)
        record = context[:sources][path]
        source = source_declaration(value: container[key], record: record)
        return unless source

        winner = source
        value = if source.is_a?(Array)
                  resolve_chain(source, context: context) { |entry| winner = entry }
                else
                  resolve_single(source, context: context)
                end
        if value.nil?
          proposal[:unresolved] += 1
          raise "Settings resolver: could not resolve #{path.inspect}" if context[:strict]

          log.warn("Settings resolver: could not resolve #{path.inspect}")
          return source unless record && container[key] == record[:value]
        else
          lease = winner.is_a?(String) && winner.match(LEASE_PATTERN)
          record = { source: source, value: value, lease: lease && { name: lease[1], key: lease[2] } }
          proposal[:assignments] << { container: container, key: key, value: value }
          proposal[:resolved] += 1
        end
        proposal[:sources][path] = record
        if record[:lease]
          proposal[:paths] << path
          proposal[:references] << record[:lease].merge(path: path, binding: record)
        end
        source
      end

      def apply_resolution(proposal:, publish:)
        snapshots = proposal[:assignments].map do |assignment|
          container = assignment[:container]
          raise FrozenError, 'Settings resolver: destination is frozen' if container.frozen?

          [container, assignment[:key], container[assignment[:key]]]
        end
        begin
          proposal[:assignments].each { |assignment| assignment[:container][assignment[:key]] = assignment[:value] }
          publish.call(proposal)
        rescue StandardError
          snapshots.reverse_each { |container, key, value| container[key] = value }
          raise
        end
        proposal
      end

      def prefetch_vault(value:, context:)
        case value
        when String
          match = value.match(VAULT_PATTERN)
          resolve_vault(match[1], match[2], context: context) if match
        when Array
          value.each { |entry| prefetch_vault(value: entry, context: context) }
        when Hash
          value.each_value { |entry| prefetch_vault(value: entry, context: context) }
        end
      end

      def resolve_vault(path, key, context: nil)
        context ||= { vault_available: vault_connected?, vault_cache: {} }
        return nil unless context[:vault_available]

        cache = context[:vault_cache]
        unless cache.key?(path)
          cache[path] = begin
            Legion::Crypt.read(path)
          rescue StandardError => e
            log.warn("Settings resolver: vault read failed for #{path}: #{e.class}=#{e.message}")
            nil
          end
        end
        data = cache[path]
        return nil unless data.is_a?(Hash)

        data.key?(key.to_sym) ? data[key.to_sym] : data[key.to_s]
      end

      def resolve_lease(name, key, context: nil)
        return context[:lease_reader].call(name: name, key: key) if context && context[:lease_reader]
        return nil unless lease_manager_available?

        Legion::Crypt::LeaseManager.instance.fetch(name, key)
      rescue StandardError => e
        log.debug("Settings resolver: lease fetch failed for #{name}##{key}: #{e.message}")
        nil
      end

      def lease_manager_available?
        defined?(Legion::Crypt::LeaseManager)
      end

      def resolvable_chain?(arr)
        arr.any? { |value| value.is_a?(String) && value.match?(URI_PATTERN) }
      end

      def count_lease_refs(hash)
        case hash
        when String then hash.match?(LEASE_PATTERN) ? 1 : 0
        when Array  then hash.sum { |value| count_lease_refs(value) }
        when Hash   then hash.sum { |_key, value| count_lease_refs(value) }
        else 0
        end
      end

      def resolve_logger_settings
        raw_logging = Legion::Settings.loader&.settings&.dig(:logging) if Legion::Settings.respond_to?(:loader)
        raw_logging.is_a?(Hash) ? raw_logging : Legion::Logging::Settings.default
      end

      private_class_method :resolution_state, :lease_sources?, :walk, :source_declaration, :declaration?,
                           :prepare_value, :apply_resolution, :prefetch_vault
    end
  end
end
