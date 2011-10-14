# -*- mode: ruby -*-
# More info at https://github.com/guard/guard#readme

guard 'rspec', :version => 2 do
  watch(%r{^spec/.+_spec\.rb$})
  watch('spec/spec_helper.rb')  { "spec/" }
  watch(%r{^lib/jkr/(.+)\.rb$})     { |m| "spec/#{m[1]}_spec.rb" }
  watch(%r{^bin/jkr$}) { "spec/bin_spec.rb" }
end
