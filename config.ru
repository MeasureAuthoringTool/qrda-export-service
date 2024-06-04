require 'bundler'

Bundler.require

require './service/web_controller'
run Sinatra::Application