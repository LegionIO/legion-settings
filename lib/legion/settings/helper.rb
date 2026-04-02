# frozen_string_literal: true

module Legion
  module Settings
    module Helper
      def settings
        ext_key = derive_settings_key
        if Legion::Settings[:extensions]&.key?(ext_key)
          Legion::Settings[:extensions][ext_key]
        else
          {}
        end
      end

      private

      def derive_settings_key
        if respond_to?(:lex_filename)
          fname = lex_filename
          (fname.is_a?(Array) ? fname.first : fname).to_sym
        else
          derive_settings_key_from_class
        end
      end

      def derive_settings_key_from_class
        name = respond_to?(:ancestors) ? ancestors.first.to_s : self.class.to_s
        parts = name.split('::')
        ext_idx = parts.index('Extensions')
        target = if ext_idx && parts[ext_idx + 1]
                   parts[ext_idx + 1]
                 else
                   parts.last
                 end
        target.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
              .to_sym
      end
    end
  end
end
