# frozen_string_literal: true

source 'https://rubygems.org'

gemspec
group :test do
  crypt_paths = [File.join(__dir__, '.ci-dependencies/legion-crypt'), File.expand_path('../legion-crypt', __dir__)]
  crypt_path = crypt_paths.find { |path| File.file?(File.join(path, 'legion-crypt.gemspec')) }
  gem 'legion-crypt', '>= 1.5.38', **(crypt_path ? { path: crypt_path } : {})
  gem 'legion-logging'
  gem 'logger'
  gem 'rake'
  gem 'rspec'
  gem 'rspec_junit_formatter'
  gem 'rubocop'
  gem 'rubocop-legion'
  gem 'simplecov'
end
