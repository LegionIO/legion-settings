# frozen_string_literal: true

require 'yaml'
require 'json'

module Legion
  module Settings
    module AgentLoader
      EXTENSIONS = %w[.yaml .yml .json].freeze
      GLOB = '*.{yaml,yml,json}'

      class << self
        def load_agents(directory)
          return [] unless directory && Dir.exist?(directory)

          Dir.glob(File.join(directory, GLOB)).filter_map do |path|
            definition = load_file(path)
            next unless definition && valid?(definition)

            definition.merge(_source_path: path, _source_mtime: File.mtime(path))
          end
        end

        def load_file(path)
          content = File.read(path)
          case File.extname(path).downcase
          when '.yaml', '.yml' then YAML.safe_load(content, symbolize_names: true)
          when '.json'         then ::JSON.parse(content, symbolize_names: true)
          end
        rescue StandardError
          nil
        end

        def valid?(definition)
          return false unless definition.is_a?(Hash)
          return false unless definition[:name].is_a?(String) && !definition[:name].empty?
          return false unless definition.dig(:runner, :functions).is_a?(Array)
          return false if definition[:runner][:functions].empty?

          true
        end
      end
    end
  end
end
