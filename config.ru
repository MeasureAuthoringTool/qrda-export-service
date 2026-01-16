require 'bundler'

Bundler.require

require './service/web_controller'
require 'datadog/auto_instrument'

run Sinatra::Application
