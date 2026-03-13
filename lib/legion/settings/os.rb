# frozen_string_literal: true

module Legion
  module Settings
    module OS
      def self.windows?
        (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
      end

      def self.mac?
        (/darwin/ =~ RUBY_PLATFORM) != nil
      end

      def self.unix?
        !OS.windows?
      end

      def self.linux?
        OS.unix? && !OS.mac?
      end

      def os
        return 'windows' if windows?
        return 'mac' if mac?
        return 'unix' if unix?

        'linux'
      end
    end
  end
end
