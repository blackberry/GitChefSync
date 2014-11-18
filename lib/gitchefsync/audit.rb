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

require 'json'
require 'gitchefsync/config'
require 'gitchefsync/io_util'
require 'gitchefsync/knife_util'
module Gitchefsync

  class Audit

    def initialize (fileLocation, type = 'cb')
      @fileLocation = fileLocation
      @ts = Time.now.to_i
      @list = Array.new
      @type = type
    end

    #adds an audit item
    def add ( item )
      @list << item
    end

    def addItem(name, version)
      item = AuditItem.new(name,version)
      add(item)
    end

    def addCookbook(cookbook,action="UPDATE",exception=nil, extra_info = nil)
      item = AuditItem.new(cookbook.name,cookbook.version,exception,action,extra_info)
      item.setCookbook(cookbook)
      add(item)
    end

    #This gives enough information
    def addEnv(name,action='UPDATE',exception=nil, extra_info=nil)
      cb = Cookbook.new(name,'','mandolin','mandolin@blackberry.com')
      addCookbook(cb,action,exception,extra_info)
    end

    #writes the audit out
    #write out a current file audit-type-current.json
    #and an audit-type-timestamp.json
    def write
      begin
        unless File.exists? @fileLocation
          FS.cmd "mkdir -p #{@fileLocation}"
        end
        fileLoc = @fileLocation + "/audit-" +@type+ @ts.to_s + ".json"
        #fileCurrent = @fileLocation + "/audit-" +@type+ "-current" + ".json"
        if @list.length > 0
          Gitchefsync.logger.debug "event_id=write_audit:file_loc=#{fileLoc}"
          file = File.open(fileLoc, "w")
          list_hash = Array.new
          @list.each do |item|
            list_hash << item.to_hash
          end
          audit_hash = Hash.new
          audit_hash['host_ip'] = (FS.cmd "hostname -I").strip
          audit_hash['host_source'] = (FS.cmd "hostname -f").strip
          audit_hash['date'] = Time.now
          #time taken from time of start of audit process -construction, until it's writing (now)
          audit_hash['audit_written_secs'] = Time.now.to_i - @ts
          audit_hash['num_items'] = list_hash.length()
          audit_hash['items'] = list_hash
          json = JSON.generate(audit_hash)
          file.write(json)
          #create sym link to this file
          latest = @fileLocation+ "/audit_" + @type + "_latest.json"
          if File.exists? latest
            File.delete latest
          end
          File.symlink(file,latest)
        else
          Gitchefsync.logger.debug "event_id=no_write_audit"
        end
      rescue IOError => e
        raise e
      ensure
        file.close unless file.nil?
      end
    end

    #returns the latest audit file
    def latest
      latest = @fileLocation+ "/audit_" + @type + "_latest.json"
      if File.exists? latest
        return latest
      end            
      file = fileFrom(-1)
      file
    end
    
    #returns the file from the latest:-1, next:-2 and so on
    #returning nil if nothing found
    def fileFrom(index)
      entries = Dir.glob(@fileLocation + "/audit-#{@type}*")
      file = nil
     
      if entries != nil && (entries.length >= -index) 
        file = entries.sort[entries.length + index]
      end
      
      file
    end

    #trims the oldest number of audit files to a max to to_num
    #Additionally archives the audit file in an audit-archive.tar.gz
    # in the fileLocation directory
    #
    #@param suffix - the audit suffix
    #@param to_num
    def trim(to_num)
      entries = Dir.glob(@fileLocation + "/audit-#{@type}*")
      Gitchefsync.logger.debug "#{@fileLocation}:#{@type} num audit files: #{entries.length}, keep=#{to_num}"
      files_trimmed = 0
      files_to_archive = Array.new
      if entries != nil
        #sorted in descending order (timestamp)
        sorted = entries.sort
        sl = sorted.length - to_num
        if sl > 0
          for i in 0..(sl-1)
            #File.delete sorted[i]
            files_to_archive << sorted[i]
          end
          files_trimmed = sl
        end
      end
      #Archiving and cleanup
      begin
        if files_to_archive.length > 0
          Gitchefsync.logger.debug "executing: tar uf #{@fileLocation}/audit-archive.tar.gz on #{flatten(files_to_archive)}"
          FS.cmd("cd #{@fileLocation} && tar uf audit-archive.tar.gz #{flatten(files_to_archive)}")
          Gitchefsync.logger.info "event_id=audit_archive:files=#{files_to_archive}"
          #delete them
          for f in files_to_archive
            File.delete(f)
          end
        end
      rescue Exception => e
        Gitchefsync.logger.error "event_id=no_write_audit:msg=#{e.message}:trace=#{e.backtrace}"
      end
      Gitchefsync.logger.debug("files trimmed:#{files_trimmed}")
      files_trimmed
    end

    def flatten(files_array)
      str = ""
      for f in files_array
        str << File.basename(f) << " "
      end
      str
    end

    #returns json structure of the latest audit
    def parseLatest
      file = latest
      if file != nil
        json = File.read(file)
        json = JSON.parse(json)
      end
      json
    end
    
    #get audit hash from the 
    #
    def auditItems(index)
      file = fileFrom(index)
      audit_list = Array.new
      
      if !file.nil?
        begin
          json = JSON.parse(File.read(file))
        rescue Exception => e
          Gitchefsync.logger.error "event_id=json_unparseable:file=#{file}"
        end 
      end
      if json.nil?
        return nil
      end
      audit_list = Array.new
      #keep backward compatibility
      if json.kind_of?(Array)
        items = json
      else
        items = json['items']
      end
      items.each do |audit_item|
        audit_list << AuditItem.new(nil,nil).from_hash(audit_item)
      end
      audit_list
            
    end
    
    def latestAuditItems
      auditItems(-1)
    end
    
    #finds the audit item by audit item name - to be used with a 
    #method latestAuditItems (above)
    #@param name - the name of the item
    #@param audit - an array of audit items
    def itemByName(name, audit)
      ret = nil
      audit.each do |item|
        
        if item.name.eql? name
          ret = item
          break
        end 
      end
      ret
    end
    def itemByNameVersion(name,version, audit)
      ret = nil
      audit.each do |item|
        
        if item.name.eql?(name) && item.version.eql?(version)
          ret = item
          break
        end 
      end
      ret
    end
    #if the json has exceptions
    def hasError (json_obj)
      ret = false
      #keep backward compatibility
      if json_obj.kind_of?(Array)
        items = json_obj
      else
        items = json_obj['items']
      end
   
      items.each do |item|
        if item['exception'] != nil then ret = true end
      end
      ret
    end
  end

  #contains functionality associated to audit information gathering
  #TODO: just reference Cookbook clas in knife_util
  class AuditItem

    def initialize(name, version, exception = nil, action = 'UPDATE', extra_info = nil, ts = Time.now)
      @name = name
      @version = version
      @ts = ts.to_i
      @exception = exception
      @action = action
      @extra_info = extra_info
    end

    def name
      @name
    end
    def version
      @version
    end
    def ex
      @exception
    end

    #types are CB and ENV
    def setType type
      @type = type
    end

    def setCookbook(cb)
      @cookbook = cb
    end

    #TODO action should be an enumeration
    def setAction action
      @action = action
    end

    def extra_info
      @extra_info 
    end
    def set_extra_info hash
      @extra_info = hash
    end
    #this method doesn't work when called when exception is created from json (from_hash)
    def to_hash
      h = Hash.new
      h[:name] = @name
      h[:ts] = @ts
      if @exception.is_a? Exception
        h[:exception] = @exception.message unless @exception == nil
      else
        h[:exception] = @exception unless @exception == nil
      end
      h[:version] = @version unless @version == nil
      h[:type] = @type unless @type == nil
      h[:action] = @action unless @action == nil
      h[:maintainer] = @cookbook.maintainer unless @cookbook == nil
      h[:maintainer_email] = @cookbook.maintainer_email unless @cookbook == nil
      h[:extra_info] = @extra_info unless @extra_info == nil
      h
    end

    def from_hash(h)
      @name = h['name']
      @ts = h['ts']
      @exception = h['exception']
      @version = h['version']
      @type = h['type']
      @action = h['action']
      @cookbook = Cookbook.new(@name,@version,h['maintainer'],h['maintainer_email'])
      @extra_info = h['extra_info']
      return self
    end
  end
end
