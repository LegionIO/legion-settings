# frozen_string_literal: true

# Spec isolation: never let the suite merge this machine's corporate DNS
# bootstrap cache (~/.legionio/settings/_dns_bootstrap.json). A real
# Legion::Settings.load would merge its top-level keys (packs, tool, kerberos,
# ...) into the test process, and validate! then reports them as unknown
# keys. Specs that exercise the enabled bootstrap path use hermetic
# cache dirs and manage LEGION_DNS_BOOTSTRAP explicitly.
ENV['LEGION_DNS_BOOTSTRAP'] = 'false'

require 'simplecov'
SimpleCov.start

require 'legion/settings'
