# frozen_string_literal: true

require_relative 'lib/legion/settings/version'

Gem::Specification.new do |spec|
  spec.name = 'legion-settings'
  spec.version       = Legion::Settings::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'Legion::Settings'
  spec.description   = 'A gem written to handle LegionIO Settings in a consistent way across extensions'
  spec.homepage      = 'https://github.com/LegionIO/legion-settings'
  spec.license       = 'Apache-2.0'
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.4'
  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.extra_rdoc_files = %w[README.md LICENSE CHANGELOG.md]
  spec.metadata = {
    'bug_tracker_uri'       => 'https://github.com/LegionIO/legion-settings/issues',
    'changelog_uri'         => 'https://github.com/LegionIO/legion-settings/blob/main/CHANGELOG.md',
    'documentation_uri'     => 'https://github.com/LegionIO/legion-settings',
    'homepage_uri'          => 'https://github.com/LegionIO/LegionIO',
    'source_code_uri'       => 'https://github.com/LegionIO/legion-settings',
    'wiki_uri'              => 'https://github.com/LegionIO/legion-settings/wiki',
    'rubygems_mfa_required' => 'true'
  }

  spec.add_dependency 'legion-json', '>= 1.2.0'
  spec.add_dependency 'legion-logging', '>= 1.5.0'
end
