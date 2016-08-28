# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'jkr/version'

Gem::Specification.new do |spec|
  spec.name          = "jkr"
  spec.version       = Jkr::VERSION
  spec.authors       = ["Yuto Hayamizu"]
  spec.email         = ["y.hayamizu@gmail.com"]
  spec.licenses      = ["GPL-3.0"]

  spec.summary       = %q{Script execution manager for experimental measurements.}
  spec.description   = %q{Jkr is a script execution manager for experimental measurements.}
  spec.homepage      = "https://github.com/as110-tkl/jkr"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'thor'
  spec.add_dependency 'term-ansicolor'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-rspec'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency "rake"
end
