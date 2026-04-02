# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Helper do
  before do
    Legion::Settings.loader = Legion::Settings::Loader.new
  end

  let(:with_lex_filename) do
    Class.new do
      include Legion::Settings::Helper

      def lex_filename
        'microsoft_teams'
      end
    end
  end

  let(:bare_class) do
    stub_const('Legion::Extensions::MyExtension::Runners::Foo', Class.new do
      include Legion::Settings::Helper
    end)
  end

  describe '#settings' do
    context 'when extension settings exist' do
      before do
        Legion::Settings.loader.load_module_settings(
          extensions: { microsoft_teams: { logger: { level: 'debug' }, custom_key: 'value' } }
        )
      end

      it 'returns extension settings via lex_filename' do
        obj = with_lex_filename.new
        expect(obj.settings[:custom_key]).to eq('value')
        expect(obj.settings[:logger][:level]).to eq('debug')
      end
    end

    context 'when extension settings exist and derived from class name' do
      before do
        Legion::Settings.loader.load_module_settings(
          extensions: { my_extension: { logger: { level: 'warn' } } }
        )
      end

      it 'derives key from class name' do
        obj = bare_class.new
        expect(obj.settings[:logger][:level]).to eq('warn')
      end
    end

    context 'when no extension settings exist' do
      it 'returns an empty hash' do
        obj = with_lex_filename.new
        expect(obj.settings).to eq({})
      end
    end
  end
end
