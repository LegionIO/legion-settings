# frozen_string_literal: true

require 'socket'
require 'concurrent/hash'
require 'legion/logging'

module Legion
  module Settings
    module Defaults
      module Client
        extend Legion::Logging::Helper

        class << self
          def defaults(**)
            Concurrent::Hash[
              hostname: system_hostname,
              address:  system_address,
              name:     "#{::Socket.gethostname.tr('.', '_')}.#{::Process.pid}",
              ready:    false
            ]
          end

          private

          def system_hostname
            ::Socket.gethostname
          rescue SocketError, SystemCallError, IOError => e
            handle_exception(e, level: :warn, operation: :system_hostname)
            'unknown'
          end

          def system_address
            addresses = ::Socket.ip_address_list.select { |address| address.ipv4? && !address.ipv4_loopback? }
            preferred = addresses.find { |address| rfc1918?(address.ip_address) }
            (preferred || addresses.first)&.ip_address || 'unknown'
          rescue SocketError, SystemCallError, IOError => e
            handle_exception(e, level: :warn, operation: :system_address)
            'unknown'
          end

          def rfc1918?(ip)
            ip.start_with?('10.') ||
              ip.match?(/\A172\.(1[6-9]|2\d|3[01])\./) ||
              ip.start_with?('192.168.')
          end
        end
      end
    end
  end
end
