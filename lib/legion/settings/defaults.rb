# frozen_string_literal: true

require 'legion/logging'
require 'legion/settings/defaults/client'
require 'legion/settings/defaults/dns'
require 'legion/settings/defaults/tls'

module Legion
  module Settings
    module Defaults
      extend Legion::Logging::Helper
    end
  end
end
