# frozen_string_literal: true

require 'resolv'
require 'concurrent/hash'
require 'legion/logging'

module Legion
  module Settings
    module Defaults
      module DNS
        extend Legion::Logging::Helper

        class << self
          def defaults(**)
            resolv_config = read_resolv_config
            Concurrent::Hash[
              fqdn:           nil, # lazy — resolved on first access via Loader#resolve_fqdn!
              default_domain: resolv_config[:search_domains]&.first,
              search_domains: resolv_config[:search_domains] || [],
              nameservers:    resolv_config[:nameservers] || [],
              bootstrap:      { enabled: true }
            ]
          end

          private

          def read_resolv_config
            config = ::Resolv::DNS::Config.default_config_hash
            {
              search_domains: config[:search]&.map(&:to_s)&.uniq,
              nameservers:    config[:nameserver]&.map(&:to_s)&.uniq
            }
          rescue ::Resolv::ResolvError, SystemCallError, IOError => e
            handle_exception(e, level: :warn, operation: :read_resolv_config)
            { search_domains: [], nameservers: [] }
          end
        end
      end
    end
  end
end
