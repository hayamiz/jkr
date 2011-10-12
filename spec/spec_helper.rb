# encoding: utf-8

$LOAD_PATH << File.expand_path('../../lib', __FILE__)
FIXTURE_DIR = File.expand_path('../fixtures', __FILE__)

require 'rubygems'
require 'jkr'

RSpec.configure do |config|
  config.mock_with :rspec

  def fixture_path(basename)
    File.expand_path(basename, FIXTURE_DIR)
  end
end

