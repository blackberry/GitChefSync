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

#helper file for parsing knife commands
#this may get refactored

require 'gitchefsync/git_util'
require 'gitchefsync/errors'
require 'gitchefsync/io_util'
require 'gitchefsync/config'

module Gitchefsync

  class KnifeUtil

    def initialize(knife, wd)
      @knife = knife
      @wd = wd
    end

    #needs knife on the command path
    #parses the knife command "cookbook list -a"
    #returns a list of cookbooks
    def listCookbooks
      list = Array.new
      str = FS.cmd "cd #{@wd} && #{@knife} cookbook list -a"
      arr_str = str.split(/\n/)
      arr_str.each do |line|
        cb_name, *cb_versions = line.split(' ')        
        cb_versions.each do |cb_version|
          list << Cookbook.new(cb_name, cb_version)
        end
      end
      list
    end

    #get a list of existing environment names on chef server
    def listEnv
      list = Array.new
      str = FS.cmd "cd #{@wd} && #{@knife} environment list"
      environments = str.split(/\n/)
      environments.each do |env|
        list << env.strip
      end
      list
    end

    #get a list of existing data bags items (in [bag, item] pairs) on chef server 
    def listDB
      list = Array.new
      str = FS.cmd "cd #{@wd} && #{@knife} data bag list"
      data_bags = str.split(/\n/)
      data_bags.each do |bag|
        data_bag_items = showDBItem bag.strip
        data_bag_items.each do |item|
          list << [bag.strip, item.strip]
        end
      end
      list
    end
    
    #get a list of existing data bag items (from specified bag) on chef server
    def showDBItem bag
      list = Array.new
      str = FS.cmd "cd #{@wd} && #{@knife} data bag show #{bag}"
      data_bag_items = str.split(/\n/)
      data_bag_items.each do |item|
        list << item.strip
      end
      list
    end
    
    #get a list of existing role names on chef server
    def listRole
      list = Array.new
      str = FS.cmd "cd #{@wd} && #{@knife} role list"
      roles = str.split(/\n/)
      roles.each do |role|
        list << role.strip
      end
      list
    end

    #checks if the cookbook name and version exist in the
    #array of cookbooks
    #@param name - name of cookbook
    #@param version - version of cookbook
    #@param list - the list of cookbooks - from listCookbooks
    def inList( name, version, list)
      found = false
      list.each do |item|
        found = true if ( (name == item.name) and (version == item.version))
      end
      found
    end

    #Checks to see if cookbook given is in list
    #uses inList method to determine it
    def isCBinList(cookbook, list)
      return inList( cookbook.name, cookbook.version, list)
    end

    #returns a list of are in list1 that are not in list2
    def subtract(list1,list2)
      list = Array.new
      list1.each do |cookbook|
        if !isCBinList(cookbook,list2)
          list << cookbook
        end
      end
      list
    end

    #delete a cookbook from the server
    def delCookbook(cb)
      begin
        FS.cmd("cd #{@wd} && knife cookbook delete #{cb.name} #{cb.version} -y" )
      rescue CmdError => e
        Gitchefsync.logger.error "event_id=cb_del:#{e.message}:e=#{e.backtrace}"
      end
    end

    #Parse metadata.rb from a given directory path
    def parseMetaData(path)
      #Gitchefsync.logger.debug "Parsing metadata: #{path}"
      if !File.exists?(File.join(path, "metadata.rb"))
        raise NoMetaDataError
      end
      contents = ""
      begin
        file = File.new(File.join(path, "metadata.rb"), "r")

        contents = file.read
        version = attr_val(contents,"version")
        name = attr_val(contents,"name")

        if name.nil?
          Gitchefsync.logger.warn "event_id=parse_meta_err_name:msg=cannot be resolved, deferring to directory name #{path}"
          name = File.basename path
        end
        #parse maintainer information
        maintainer = attr_val(contents,"maintainer")
        email = attr_val(contents,"maintainer_email")

        #puts "matched:#{name}:#{version}"
        return Cookbook.new(name, version,maintainer,email)
      rescue Exception => e
        puts e.backtrace
        Gitchefsync.logger.error "#{e.backtrace}"
        raise KnifeError, "Unable to parse data: file=#{path}/metadata.rb #{contents}"
      ensure
        file.close unless file.nil?
      end
    end

    def attr_val(contents, name)
      m1 = contents.match(/#{name}\s+['|"](.*)['|"]/)
      val = nil
      if m1 != nil && m1.length == 2
        val = m1[1]
      else
        Gitchefsync.logger.warn "event_id=parse_warn:name=#{name}"
      end
      val
    end
  end #end class

  #A cookbook description
  #may include a hash or other description
  class Cookbook

    def	initialize(name,version,maintainer = "", maintainer_email = "")
      @name = name
      @version = version
      @maintainer = maintainer
      @maintainer_email = maintainer_email
    end

    def name
      @name
    end

    def version
      @version
    end

    def maintainer
      @maintainer
    end

    def setMaintainer(maintainer)
      @maintainer = maintainer
    end

    def maintainer_email
      @maintainer_email
    end

    def setMaintainer_email(maintainer_email)
      @maintainer_email = maintainer_email
    end

    def to_s
      return @name + "_" + @version
    end

    #name convention of how berks packages
    def berksTar
      return @name + "-" + @version + ".tar.gz"
    end
  end
end
