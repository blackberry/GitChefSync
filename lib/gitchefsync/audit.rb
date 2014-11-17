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
      @list << item.to_hash
    end

    def addItem(name, version)
      item = AuditItem.new(name,version)
      add(item)
    end

    def addCookbook(cookbook,action="UPDATE",exception=nil)
      item = AuditItem.new(cookbook.name,cookbook.version,exception,action)
      item.setCookbook(cookbook)
      add(item)
    end

    #This gives enough information
    def addEnv(name,action='UPDATE',exception=nil)
      cb = Cookbook.new(name,'','mandolin','mandolin@blackberry.com')
      addCookbook(cb,action,exception)
    end

    #writes the audit out
    #write out a current file audit-type-current.json
    #and an audit-type-timestamp.json
    def write
      begin
        fileLoc = @fileLocation + "/audit-" +@type+ @ts.to_s + ".json"
        #fileCurrent = @fileLocation + "/audit-" +@type+ "-current" + ".json"
        if @list.length > 0
          Gitchefsync.logger.debug "event_id=write_audit:file_loc=#{fileLoc}"
          file = File.open(fileLoc, "w")
          json = JSON.generate(@list)
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
      entries = Dir.glob(@fileLocation + "/audit-#{@type}*")
      file = nil
      if entries != nil
        file = entries.sort[entries.length-1]
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

    def latestAuditItems
      json = parseLatest
      if json.nil?
        raise AuditError, "No json available"
      end
      audit_list = Array.new
      json.each do |audit_item|
        audit_list << AuditItem.new(nil,nil).from_hash(audit_item)
      end
      audit_list
    end

    #if the json has exceptions
    def hasError (json_obj)
      ret = false
      json_obj.each do |item|
        if item['exception'] != nil then ret = true end
      end
      ret
    end
  end

  #contains functionality associated to audit information gathering
  #TODO: just reference Cookbook clas in knife_util
  class AuditItem

    def initialize(name, version, exception = nil, action = 'UPDATE', ts = Time.now)
      @name = name
      @version = version
      @ts = ts.to_i
      @exception = exception
      @action = action
    end

    def name
      @name
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
      return self
    end
  end
end
