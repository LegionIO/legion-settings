# frozen_string_literal: true

require 'concurrent/map'

module Legion
  module Settings
    module Extensions
      # Thread-safe registry store backed by Concurrent::Map.
      #
      # Each store holds one type of entry (extensions, runners, or tools).
      # Entries are plain hashes keyed by normalized string name.
      # Read operations return frozen duplicates so callers cannot mutate internals.
      class Store
        def initialize
          @map = Concurrent::Map.new
        end

        def register(name, metadata = {})
          key = normalize_key(name)
          entry = metadata.merge(name: key, registered_at: Time.now)
          @map[key] = entry
          entry.freeze
        end

        def find(name)
          @map[normalize_key(name)]&.dup&.freeze
        end

        def all
          snapshot = @map.values.map(&:dup)
          snapshot.each(&:freeze)
          snapshot.freeze
        end

        def filter(**_criteria, &block)
          result = @map.values.map(&:dup)
          result.select!(&block) if block
          result.each(&:freeze)
          result.freeze
        end

        def delete(name)
          @map.delete(normalize_key(name))
        end

        def delete_where(&block)
          @map.each_pair { |k, v| @map.delete(k) if block.call(v) }
        end

        def update(name, **extra)
          key = normalize_key(name)
          old_entry = @map[key]
          return nil unless old_entry

          updated = old_entry.dup.merge(extra.merge(updated_at: Time.now))
          @map[key] = updated
          updated.freeze
        end

        def size
          @map.size
        end

        def any?
          @map.size.positive?
        end

        def clear
          @map.clear
        end

        private

        def normalize_key(name)
          name.to_s
        end
      end
    end
  end
end
