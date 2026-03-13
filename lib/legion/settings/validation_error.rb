# frozen_string_literal: true

module Legion
  module Settings
    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(format_message)
      end

      private

      def format_message
        count = @errors.length
        label = count == 1 ? 'error' : 'errors'
        lines = @errors.map do |err|
          "  [#{err[:module]}] #{err[:path]}: #{err[:message]}"
        end
        "#{count} configuration #{label} detected:\n\n#{lines.join("\n")}"
      end
    end
  end
end
