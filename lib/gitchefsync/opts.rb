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

require 'gitlab'
require 'gitchefsync/errors'
module Gitchefsync

  module Parser

    def self.parseOpts (args)
      options = {}
      begin

        opt_parser = OptionParser.new do |opts|
          opts.banner = "Usage: sync_all.rb --private_token=xyz OR LDAP credentials"
          options[:private_token] = ''
          opts.on('-t', '--private_token token','gitlab private token') do |token|
            options[:private_token] = token
          end
          options[:config_file] = './sync-config.json'
          opts.on('-c', '--config file','path to config file') do |token|
            options[:config_file] = token
          end
          options[:login] = ''
          opts.on('-l','--login login','Required when token not set') do |login|
            options[:login] = login
          end
          options[:password] = ''
          opts.on('-p','--password password','Required when token not set') do |pass|
            options[:password] = pass
          end
          opts.on('-s','--syslog',"Enable syslog") do |syslog|
            options[:syslog] = true
          end
          opts.on('-u', '--giturl', "Gitlab url") do |giturl|
            Gitlab.endpoint = giturl
          end
        end

        opt_parser.parse! (args)

        json = File.read(options[:config_file])

        j_config = JSON.parse(json)
        options[:config] = j_config
        options[:git_local] = j_config['working_directory']
        options[:knife_config] = j_config['knife_file']
        options[:groups] = j_config['git_groups']
        options[:stage_cookbook_dir] = j_config['tmp_dir']

        #set gitlab token and ensure git url for backward compatibility
        if Gitlab.endpoint == nil
          Gitlab.endpoint = 'https://gitlab.rim.net/api/v3'
        end
        if options[:private_token].empty? && !options[:login].empty? && !options[:password].empty?
          puts "using credentials"
          options[:private_token] = Gitlab.session(options[:login],options[:password]).to_hash['private_token']
        end

      rescue Exception => e
        puts e.backtrace
        raise(ConfigError,e.message,e.backtrace)
      end
      options
    end
  end
end
