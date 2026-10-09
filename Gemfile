source "https://rubygems.org"

gem 'sinatra', '>= 4.2.0'
gem 'puma', '>= 8.0.2'
gem 'passenger', '>= 6.1.1'
gem 'rest-client'
gem 'cqm-reports', '4.1.9'
gem 'rackup', '~> 2.2', '>= 2.2.0'
gem 'rack-contrib', '~> 2.5', '>= 2.5.0'
gem 'jwt', '>= 3.2.0'
gem 'mongoid', '~> 9.1.1'
gem 'rubyzip', '~> 3.4.0'
gem 'datadog', '>= 2.31.0'

# MAT-10345 Temporary override for CVE-2026-71847 remediation.
# Removes vulnerable json versions < 2.21.2.
gem 'json', '>= 2.21.2'

gem 'cqm-models', :git => 'https://github.com/projecttacoma/cqm-models', :branch => 'master'

group :test do
  gem 'minitest'
  gem 'rack-test'
end
