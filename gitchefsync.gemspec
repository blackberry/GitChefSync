# coding: utf-8
# Gitchefsync - git to chef sync toolset
#
# Copyright 2014, BlackBerry, Inc.
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gitchefsync/version'

Gem::Specification.new do |spec|
  spec.name          = "gitchefsync"
  spec.version       = Gitchefsync::VERSION
  spec.authors       = ["Marcus Simonsen", "Phil Oliva"]
  spec.email         = ["msimonsen@blackberry.com","poliva@blackberry.com"]
  spec.summary       = "Git to Chef sync"
  spec.description   = "Tool(s) to help synchronize Git -> Chef server"
  spec.license       = "Apache 2.0"

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
  spec.homepage = "https://github.com/blackberry/GitChefSync"

  
end
