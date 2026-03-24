# frozen_string_literal: true

module Legion
  module Settings
    module Validators
      module Tls
        TLS_BLOCKS = %i[transport data cache security api].freeze

        class << self
          def validate(settings)
            warnings = []
            errors   = []

            validate_transport_tls(settings, warnings)
            validate_data_tls(settings, warnings, errors)
            validate_security_mtls(settings, warnings)
            validate_api_tls(settings, warnings, errors)

            { valid: errors.empty?, warnings: warnings, errors: errors }
          end

          private

          def validate_transport_tls(settings, warnings)
            tls = dig_tls(settings, :transport)
            return unless tls[:enabled]

            warnings << 'transport.tls: verify is none — peer verification disabled, connections are unauthenticated' if tls[:verify].to_s == 'none'

            check_cert_path(tls[:cert], 'transport.tls.cert', warnings)
            check_cert_path(tls[:key],  'transport.tls.key',  warnings)
            check_cert_path(tls[:ca],   'transport.tls.ca',   warnings)
          end

          def validate_data_tls(settings, warnings, errors)
            tls = dig_tls(settings, :data)
            return unless tls[:enabled]

            sslmode = tls[:sslmode].to_s
            return if sslmode.empty? || sslmode == 'verify-full'

            env = settings[:env].to_s
            msg = "data.tls: sslmode '#{sslmode}' should be 'verify-full' to prevent MITM attacks"
            if env == 'production'
              errors << msg
            else
              warnings << msg
            end
          end

          def validate_security_mtls(settings, warnings)
            mtls = settings.dig(:security, :mtls) || {}
            mtls = symbolize_keys(mtls)
            return unless mtls[:enabled]

            check_cert_path(mtls[:cert], 'security.mtls.cert', warnings)
            check_cert_path(mtls[:key],  'security.mtls.key',  warnings)
            check_cert_path(mtls[:ca],   'security.mtls.ca',   warnings)
          end

          def validate_api_tls(settings, _warnings, errors)
            tls = dig_tls(settings, :api)
            return unless tls[:enabled]

            cert = tls[:cert]
            key  = tls[:key]

            errors << 'api.tls: enabled but api.tls.cert is not set' if cert.nil? || cert.to_s.empty?

            errors << 'api.tls: enabled but api.tls.key is not set' if key.nil? || key.to_s.empty?
          end

          def dig_tls(settings, component)
            raw = settings.dig(component, :tls) || {}
            symbolize_keys(raw)
          rescue StandardError
            {}
          end

          def check_cert_path(path, label, warnings)
            return if path.nil? || path.to_s.empty?
            return if path.to_s.start_with?('vault://', 'env://', 'lease://')
            return if ::File.exist?(path.to_s)

            warnings << "#{label}: path '#{path}' does not exist"
          end

          def symbolize_keys(hash)
            return {} unless hash.is_a?(Hash)

            hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
          end
        end
      end
    end
  end
end
