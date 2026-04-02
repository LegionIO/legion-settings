# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/settings'
require 'legion/settings/project_env'

RSpec.describe Legion::Settings::ProjectEnv do
  let(:tmpdir) { Dir.mktmpdir('legion_project_env_test') }

  after { FileUtils.rm_rf(tmpdir) }

  # -----------------------------------------------------------------------
  # find_project_env_file
  # -----------------------------------------------------------------------
  describe '.find_project_env_file' do
    it 'returns nil when no .legionio.env file exists in the tree' do
      empty_dir = File.join(tmpdir, 'empty')
      FileUtils.mkdir_p(empty_dir)
      expect(described_class.find_project_env_file(start_dir: empty_dir)).to be_nil
    end

    it 'finds .legionio.env in the start directory' do
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, '')
      expect(described_class.find_project_env_file(start_dir: tmpdir)).to eq(env_file)
    end

    it 'finds .legionio.env in a parent directory' do
      child_dir = File.join(tmpdir, 'child', 'grandchild')
      FileUtils.mkdir_p(child_dir)
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, '')
      expect(described_class.find_project_env_file(start_dir: child_dir)).to eq(env_file)
    end

    it 'prefers the nearest ancestor' do
      child_dir = File.join(tmpdir, 'child')
      FileUtils.mkdir_p(child_dir)
      parent_file = File.join(tmpdir, '.legionio.env')
      child_file  = File.join(child_dir, '.legionio.env')
      File.write(parent_file, '')
      File.write(child_file, '')
      expect(described_class.find_project_env_file(start_dir: child_dir)).to eq(child_file)
    end

    it 'defaults start_dir to Dir.pwd when omitted' do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, '')
      expect(described_class.find_project_env_file).to eq(env_file)
    end
  end

  # -----------------------------------------------------------------------
  # parse_env_file
  # -----------------------------------------------------------------------
  describe '.parse_env_file' do
    def write_env(content)
      path = File.join(tmpdir, '.legionio.env')
      File.write(path, content)
      path
    end

    it 'parses a simple flat key' do
      path = write_env("foo=bar\n")
      expect(described_class.parse_env_file(path)).to eq(foo: 'bar')
    end

    it 'parses a dot-notation key into a nested hash' do
      path = write_env("llm.default_model=claude-sonnet\n")
      expect(described_class.parse_env_file(path)).to eq(llm: { default_model: 'claude-sonnet' })
    end

    it 'parses deeply nested dot-notation keys' do
      path = write_env("transport.connection.host=rabbit.local\n")
      expect(described_class.parse_env_file(path)).to eq(
        transport: { connection: { host: 'rabbit.local' } }
      )
    end

    it 'ignores comment lines' do
      path = write_env("# this is a comment\nfoo=bar\n")
      expect(described_class.parse_env_file(path)).to eq(foo: 'bar')
    end

    it 'ignores blank lines' do
      path = write_env("\n\nfoo=bar\n\n")
      expect(described_class.parse_env_file(path)).to eq(foo: 'bar')
    end

    it 'preserves equals signs in the value' do
      path = write_env("auth.token=abc=def==ghi\n")
      expect(described_class.parse_env_file(path)[:auth][:token]).to eq('abc=def==ghi')
    end

    it 'returns an empty hash for an empty file' do
      path = write_env('')
      expect(described_class.parse_env_file(path)).to eq({})
    end

    it 'strips leading/trailing whitespace from keys and values' do
      path = write_env("  llm.model  =  sonnet  \n")
      expect(described_class.parse_env_file(path)).to eq(llm: { model: 'sonnet' })
    end

    it 'skips malformed lines without raising' do
      path = write_env("this_has_no_equals\nfoo=bar\n")
      expect { described_class.parse_env_file(path) }.not_to raise_error
      expect(described_class.parse_env_file(path)).to eq(foo: 'bar')
    end

    it 'parses multiple keys correctly' do
      path = write_env("llm.model=haiku\ncache.driver=redis\n")
      result = described_class.parse_env_file(path)
      expect(result[:llm][:model]).to eq('haiku')
      expect(result[:cache][:driver]).to eq('redis')
    end
  end

  # -----------------------------------------------------------------------
  # load_into
  # -----------------------------------------------------------------------
  describe '.load_into' do
    it 'returns nil when no .legionio.env file is found' do
      empty_dir = File.join(tmpdir, 'no_env')
      FileUtils.mkdir_p(empty_dir)
      settings = {}
      expect(described_class.load_into(settings, start_dir: empty_dir)).to be_nil
    end

    it 'returns the path of the loaded file' do
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "foo=bar\n")
      settings = {}
      expect(described_class.load_into(settings, start_dir: tmpdir)).to eq(env_file)
    end

    it 'merges parsed values into the settings hash' do
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "llm.default_model=haiku\n")
      settings = {}
      described_class.load_into(settings, start_dir: tmpdir)
      expect(settings[:llm][:default_model]).to eq('haiku')
    end

    it 'env file values override existing settings' do
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "cache.driver=redis\n")
      settings = { cache: { driver: 'dalli', enabled: true } }
      described_class.load_into(settings, start_dir: tmpdir)
      expect(settings[:cache][:driver]).to eq('redis')
      expect(settings[:cache][:enabled]).to eq(true)
    end
  end
end

# -----------------------------------------------------------------------
# Integration: Legion::Settings.load_project_env
# -----------------------------------------------------------------------
RSpec.describe Legion::Settings do
  let(:tmpdir) { Dir.mktmpdir('legion_settings_project_env_test') }

  before { described_class.reset! }
  after do
    described_class.reset!
    FileUtils.rm_rf(tmpdir)
  end

  describe '.load_project_env' do
    it 'returns nil when no .legionio.env is found' do
      empty = File.join(tmpdir, 'empty')
      FileUtils.mkdir_p(empty)
      expect(described_class.load_project_env(start_dir: empty)).to be_nil
    end

    it 'loads the .legionio.env file and makes values accessible via []' do
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "project_env_key=project_value\n")
      described_class.load_project_env(start_dir: tmpdir)
      expect(described_class[:project_env_key]).to eq('project_value')
    end

    it 'env file values override global settings' do
      described_class.merge_settings('cache', { driver: 'dalli' })
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "cache.driver=redis\n")
      described_class.load_project_env(start_dir: tmpdir)
      expect(described_class[:cache][:driver]).to eq('redis')
    end

    it 'invalidates the loader digest when project env changes settings' do
      old_bootstrap = ENV.fetch('LEGION_DNS_BOOTSTRAP', nil)
      ENV['LEGION_DNS_BOOTSTRAP'] = 'false'
      described_class.load
      before_digest = described_class.get.hexdigest

      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "cache.driver=redis\n")
      described_class.load_project_env(start_dir: tmpdir)

      expect(described_class.get.hexdigest).not_to eq(before_digest)
    ensure
      ENV['LEGION_DNS_BOOTSTRAP'] = old_bootstrap
    end
  end

  describe 'resolution order: overlay > project env > global' do
    it 'overlay beats project env beats global' do
      described_class.merge_settings('mymod', { mode: 'global' })
      env_file = File.join(tmpdir, '.legionio.env')
      File.write(env_file, "mymod.mode=project\n")
      described_class.load_project_env(start_dir: tmpdir)

      # project env overrides global
      expect(described_class[:mymod][:mode]).to eq('project')

      # overlay overrides project env
      described_class.with_overlay(mymod: { mode: 'overlay' }) do
        expect(described_class[:mymod][:mode]).to eq('overlay')
      end

      # back to project env after overlay exits
      expect(described_class[:mymod][:mode]).to eq('project')
    end
  end
end
