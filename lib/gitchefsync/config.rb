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

require 'gitchefsync/opts'
require 'logger'
#Not available till ruby 2.0
#require 'syslog/logger'
require 'syslog'
require 'gitchefsync/log'

#Central point of configuration
module Gitchefsync
  module Configuration

    REL_BRANCH = 'master'

        
    def initialize(opts)
      @git_bin = 'git'

    end

    def configure(options)
      
      @options = options
      config = options[:config]
      @git_bin = config['git']
      @berks = config['berks']
      @knife = config['knife']
      @git_local = options[:git_local]
      @token =  options[:private_token]
      @stage_dir = config['stage_dir']
      @audit_dir = config['stage_dir'] + "/audit"
      config['audit_dir'] = @audit_dir
      @rel_branch = config['release_branch']
      @rel_branch ||= 'master'
      @stage_cb_dir = options[:stage_cookbook_dir]
      @stage_cb_dir ||= '/tmp/cookbooks'
      @berks_upload = false
      @audit_keep_trim = config['audit_keep_trim'] 
      @audit_keep_trim ||= 20
        
      #backward compatibility for "sync_local" attribute
      if config['sync_local'].is_a? String 
        if config['sync_local'] == "true"
          config['sync_local'] = true
          config[:sync_local] = true
        else
          config['sync_local'] = false
          config[:sync_local] = false
        end
      end
      options[:syslog] ?
        @log = Gitchefsync::Log::SysLogger.new('gitchefsync') :
        @log = Logger.new(STDOUT)
      #json based configuration
      @config = config
     
    end

    def parseAndConfigure(args)
      include Parser

      $args = args.clone
      $opts = Parser.parseOpts args
      configure $opts
      
      #instantiate audit
      #@audit = Audit.new(@config['stage_dir'] )
         
      return $opts
    end
    
    def logger
      @log
    end
    
    def self.log 
      Gitchefsync.logger()
      
    end
    
    def configuration
      @config
    end
    
    def options
      @options
    end
    
    
  end
end
