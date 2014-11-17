# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gitchefsync/version'

Gem::Specification.new do |spec|
  spec.name          = "gitchefsync"
  spec.version       = Gitchefsync::VERSION
  spec.authors       = ["Marcus Simonsen"]
  spec.email         = ["msimonsen@blackberry.com"]
  spec.summary       = "Git to Chef sync"
  spec.description   = "Tool(s) to help synchronize Git -> Chef server"
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  ##Need to figure out the right dependency versions first, otherwise errors out
  #spec.add_runtime_dependency 'chef'
  #spec.add_runtime_dependency 'berkshelf'
  spec.add_runtime_dependency "gitlab", '~> 3.0.0'
  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.homepage = "https://gitlab.rim.net/mandolin/gitchefsync/tree/master"

  
end
