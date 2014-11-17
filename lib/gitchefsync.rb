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

require 'optparse'
require 'gitlab'
require 'json'
require 'open3'
require 'gitchefsync/version'
require 'gitchefsync/git_util'
require 'gitchefsync/errors'
require 'gitchefsync/opts'
require 'gitchefsync/io_util'
require 'gitchefsync/env_sync'
require 'gitchefsync/audit'
require 'gitchefsync/knife_util'
require 'gitchefsync/config'
require 'gitchefsync/common'
require 'gitchefsync/notify'
require 'gitchefsync/schedule'

module Gitchefsync
   # include Gitchefsync::Configuration
      
  #A summary of actions and cli options
  def self.help
    puts "Usage: gitchefsync [operation] -c config_file.json -t gitlab_token -u gitlab_url [--login=gitlabuser --password=gitlabpassword --syslog]"
    puts "\tgitchefsync runMasterSync"
    puts "\tgitchefsync runSousSync"
    puts "\tgitchefsync syncCookbooks"
    puts "\tgitchefsync syncCookbooksLocal"
    puts "\tgitchefsync syncEnv"
    puts "\tgitchefsync stagedUpload"
    puts "\tgitchefsync reconcile"
    puts "\tgitchefsync gitCleanup"
    puts "\tgitchefsync trimAudit"
  end
  
  #trims the environment and cookbook audits, keeping @audit_keep_trim
  #number of files
  def self.trimAudit
    logger.debug("event_id=trim_audit_files:keep=#{@audit_keep_trim}")
    audit = Audit.new(@audit_dir, 'env' )
    audit.trim(@audit_keep_trim)
    
    audit = Audit.new(@audit_dir, 'cb' )
    audit.trim(@audit_keep_trim)
    
  end
  
  def self.notifyFromAudit
    
    notification = Notification.new(@config['smtp_server'])
    
    notification.singleNotifyFromAudit(@audit_dir, 'cb',@config['default_notify_email'] )
    notification.singleNotifyFromAudit(@audit_dir,'env',@config['default_notify_email']) 
    
    notification.close
  end
    
  
  #performs a git synchronization of cookbooks, pulling 
  #in information from configured group of gitlab groups
  #from each of the configured groups in sync-config.json
  #pull all the projects associated with each group
  #installed in working_directory, as specified in sync-config.json
  #
  #Each repository will only pull from configured release branch
  #And fetch tags associated with that branch
  #The last process is to invoke syncCookbooksLocal
  def self.syncCookbooks 
    include  FS
    
    
    
    FS.knifeReady(@options[:git_local], @options[:knife_config])
    @knife_ready = true
    
    if !@config['sync_local'] 
     
      self.pullCookbooks()
    else
      logger.warn "event_id=Skip_cookbook_git_sync:path=#{@git_local}"
    end
    #git is synchronized (other than deletion - see gitCleanup if you want to clean up)
    #move to synchronization on the local file system
    self.syncCookbooksLocal
  end
 
  #Pull all the cookbooks that are configured via the configuration policy
  #in sync_config.json
  #For auto-discovery will pull every project and every project from each group
  #that this user will have access to
  def self.pullCookbooks
    Gitlab.private_token = @token
    
    group_names = (@config['gitlab_group_names'] or [])
    group_ids = (@config['gitlab_group_ids'] or [])
  
    if @config['gitlab_autodiscover']
      # Find all projects known by gitlab-token
      # Determine which of these projects contains .gitchefsync.yml at HEAD of default branch
      self.pullAllProjects
    else 
      logger.debug "Synchronizing group names: #{group_names}"
      logger.debug "Synchronizing group ids: #{group_ids}"
      self.getAllGroupIDs(group_names, group_ids).each do |groupid|
        group = Gitlab.group groupid
        projects = group.to_hash['projects']
        projects.each do |project|
          self.pullProject(project)
        end
      end
    end

    repo_list = @config['cookbook_repo_list']
    
    #explicit set list of cookbook repositories
    if repo_list != nil
      logger.info "event_id=repo_list_sync:config=#{@config['cookbook_repo_list']}"
      repo_list.each do |repo|
        #match the "path: full_path/repo.git"
        match = repo.split('/')
        if match == nil
          raise GitError, "Can not parse #{repo}"
        end
        path = match[match.length-1]
        path = path[0..path.length-5]
        begin
          self.updateGit(@git_local + "/" + path, repo )
        rescue GitError => e
          logger.error "event_id=git_error:msg=#{e.message}:trace=#{e.backtrace}"
          logger.error "event_id=remove_project_path: #{project_path}"
          FS.cmd "rm -rf #{project_path}"
        end
      end
    end
  end
  #cycle through the working directory to see if a repo got deleted
  #by checking that the remote repository got deleted
  def self.gitCleanup
    include Git,FS
    cookbook_dirs = Dir.entries(@git_local).reject! {|item| item.start_with?(".") }
    cookbook_dirs.each do |dir|
      if !Git.remoteExists(dir,@rel_branch)
        
        #delete tar balls associated with this repo, the directory name 
        #subsequent calls to "reconcile" will clean up
        cookbook = KnifeUtil.new(@knife,dir).parseMetaData(dir)
        if cookbook != nil
          #remove all files associated with this cookbook name
          files = @stage_dir +"/" + cookbook.name() + "-*tar.gz"
          FS.cmd("rm -fr #{files}")
      
        end
      end
    end      
  end
  
  #For each repository in the working directory (defined by sync-config.json)
  #checkout each tag 
  # 1. upload to the configured chef server via a berks upload
  # 2. package the cookbook in the stage_dir (defined in sync-config.json)
  # 3. create an audit of each cookbook that was created
  #
  #param options - the list of options
  def self.syncCookbooksLocal 
    include FS,Git
   
    logger.info "event_id=stage_cookbooks:git_local=#{@git_local}"
    FS.knifeReady(@options[:git_local], @options[:knife_config]) unless @knife_ready
    ret_status = Hash.new
    
    
    #not sure if this should be globally governed?
    audit = Audit.new(@audit_dir, 'cb')
   
    
    knifeUtil = KnifeUtil.new(@knife, @git_local)
    #Have a delta point: interact with the chef server to identify delta
    listCB = knifeUtil.listCookbooks
    #list of cookbooks processed
    list_processed = Array.new
    cookbook_dirs = Dir.entries(@git_local).reject! {|item| item.start_with?(".") }
    cookbook_dirs.each do |dir|

      path = File.join(@git_local, dir)
      
      arr_tags = Git.branchTags(path, @rel_branch)
      
      
      #match tag against version in metadata.rb
      #possible error condition
      arr_tags.each do |tag|
        
        
        begin
          logger.debug "event_id=git_checkout:path=#{path}:tag=#{tag}"
          Git.cmd "cd #{path} && #{@git_bin} checkout #{tag}"
          
          cb = self.processCookbook(path,audit)
          list_processed << @stage_dir + "/" + cb.berksTar() unless cb.nil?
          
        rescue NoMetaDataError => e
          #No audit written on failure to parse metadata
          logger.info "event_id=nometadata:dir=#{dir}"
          next
        rescue KnifeError => e
          #No audit written on failure to parse metadata
          logger.error "event_id=cmd_error:#{e.message}:trace=#{e.backtrace}"
          next
        rescue NoBerksError => e
          #No audit written on no Berks file
          logger.error "event_id=cmd_error:#{e.message}:trace=#{e.backtrace}"
          next
        
        rescue Exception => e
          
          logger.error "event_id=git_error:msg=#{e.message}:trace=#{e.backtrace}"
          cookbook = Cookbook.new(dir,tag) if cookbook.nil?
          audit.addCookbook(cookbook,"ERROR",e)
          next
        end
      end
    end
    
    #compared list_processed with what is in stage
    #and delete the tars
    stage = @stage_dir + "/*tar.gz"
    existing = Dir.glob(stage)
    to_del = existing - list_processed
    logger.info "event_id=list_tar_delta:del+list=#{to_del}"
    to_del.each do |file| 
      File.delete(file)
    end
    #reconcile method will actually delete the cookbooks from server
     
    #write out the audit file
    audit.write
    #clean the audit files
    audit.trim(@audit_keep_trim)
  end
  
  #Process the cookbook from the working directory's path (or path specified)
  #If the cookbook exists on the server, don't package or upload
  #we may want to add one other condition to force this
  #packaging behaviour and hence rsync
  def self.processCookbook(path,audit)
    knifeUtil = KnifeUtil.new(@knife, @git_local)
    cookbook = knifeUtil.parseMetaData(path)
    logger.debug "event_id=processing:cookbook=#{cookbook}"
    
    
    if cookbook != nil
      stage_tar = @config['stage_dir'] +"/" + cookbook.berksTar()
      tar_exists = File.exists?(stage_tar)
    end
    
    begin
      
      #get some git historical info
      extra = Hash.new
      extra['sha'] = (Git.cmd "cd #{path} && git log -1 --pretty=%H").chomp
      extra['author_email'] = (Git.cmd "cd #{path} && git log -1 --pretty=%ce").chomp
      extra['date'] = (Git.cmd "cd #{path} && git log -1 --pretty=%cd").chomp
      extra['subject'] = (Git.cmd "cd #{path} && git log -1 --pretty=%s").chomp
        
      if  (cookbook !=nil && (!knifeUtil.isCBinList(cookbook, self.serverCookbooks()) || !tar_exists ))
        berks_tar = self.stageBerks(path ,  @config['stage_dir'])
        #upload cookbooks still puts a Berksfile, will refactor this method
        self.uploadBerks(path)
        logger.debug("event_id=staging:cookbook=#{cookbook}:berks_tar=#{berks_tar}")
        self.stageCBUpload(berks_tar, @stage_cb_dir, knifeUtil, self.serverCookbooks())
        audit.addCookbook(cookbook,"UPDATE",nil,extra) if berks_tar.nil?
        logger.info "event_id=cookbook_staged:cookbook=#{cookbook}"
  
      elsif cookbook !=nil && @config['force_package']
        logger.info "event_id=cookbook_force_package:cookbook=#{cookbook}"
        self.stageBerks(path, @config['stage_dir'])
       elsif cookbook != nil
        audit.addCookbook(cookbook, "EXISTING",nil,extra)
        logger.info "event_id=cookbook_untouched:cookbook=#{cookbook}"
      end
    rescue BerksError => e
      logger.error "event_id=berks_package_failure:msg=#{e.message}:trace=#{e.backtrace}"
      audit.addCookbook(cookbook, "ERROR", e,  extra)
    end
    
    Git.cmd "cd #{path} && git clean -xdf"
    return cookbook
  end

  #do a berks upload of the path
  #this will end up using sources in Berksfile
  #which is not good for the production sync
  def self.uploadBerks(path)
    include FS
    
    begin
      if File.exists?(File.join(path, "Berksfile"))
        logger.debug "Berkshelf orginally used in this tagged version of cookbook"
      elsif File.exists?(File.join(path, "metadata.rb"))
        logger.debug "Berkshelf was not orginally used in this tagged version of cookbook"
        logger.info "event_id=create_berks:path=#{path}"
        berksfile = File.new(File.join(path, "Berksfile"), "w")
  
        version = FS.cmd "#{@berks} -v"
        if version.start_with?("3.")
            berksfile.puts("source \"https:\/\/api.berkshelf.com\"\nmetadata")
        else
            berksfile.puts("site :opscode\nmetadata")
        end
        berksfile.close
      else
        raise NoBerksError, "Unable to locate Berks file for #{path}"
      end
      
      if @berks_upload
        logger.info "event_id=berks_install_upload&cookbook=#{path}"
                
        out = FS.cmdBerks "cd #{path} && rm -f Berksfile.lock && #{@berks} install && #{@berks} upload"
        
        logger.info "event_id=berks_upload=#{out}"
      else
        logger.debug "event_id=no_berks_upload&cookbook=#{path}"
      end
    rescue Exception => e
      raise BerksError.new(e.message)
    end
  end
  

  #do and install and package the berks cookbook
  #in a staging directory
  #returns the path to the berks tar file
  def self.stageBerks(path, stage_dir)
    include FS
    
    begin
      if File.exists?(File.join(path,"Berfile.lock"))
        raise BerksLockError, "Berks lock file found"
      end
      if File.exists?(File.join(path, "Berksfile"))
        logger.debug "event_id=Stage_cookbook:path=#{path}"
        
              
        #get the name from metadata if available
        cookbook = KnifeUtil.new(@knife,path).parseMetaData(path)
        if cookbook != nil
          #remove residual tar - this could be problematic if there is are tars in the 
          #cookbook
          FS.cmd "rm -f #{path}/#{cookbook.berksTar}"
          
          #Since cmdBerks doesn't raise exception must provide alternate check
          out = FS.cmdBerks "cd #{path} && #{@berks} package #{cookbook.berksTar}"
          logger.info "event_id=berks_package=#{out}"
          if File.exists? "#{path}/#{cookbook.berksTar}"
            
            # empty tarballs in staging produced errors in staged upload
            # this can happen when Berksfile is a blank file
            file_count = FS.cmd "tar tf #{path}/#{cookbook.berksTar} | wc -l"
            if file_count.to_i > 1
              FS.cmd "mv #{path}/#{cookbook.berksTar} #{stage_dir}"
            else 
              logger.info "event_id=berks_package_produced_empty_tarball: #{path}/#{cookbook.berksTar}"
              FS.cmd "rm -f #{path}/#{cookbook.berksTar}" 
              raise BerksError.new("`berks package` produced empty tarball: #{path}/#{cookbook.berksTar}")
            end
            
          else
            logger.info "event_id=berks_package_failed: #{path}/#{cookbook.berksTar}" 
            raise BerksError.new("Something went wrong generating berks file: #{out}")
          end
        
          return "#{stage_dir}/#{cookbook.berksTar}"
        end
      else
        raise NoBerksError, "Unable to locate Berks file for #{path}"
      end
    
    rescue NoBerksError,BerksLockError => e 
      raise e
    rescue Exception => e
      raise BerksError.new(e.message) 
    end
    
  end


  
  #Find all versions of cookbooks from the server via knife command
  #From the stage directory, do knife upload on each of the tars
  #if the cookbook and version exists on the server don't attempt the knife upload
  #Each tar file is extracted to a cookbook directory
  #where a knife upload -a is attempted on the entire directory
  #as each tar is processed the directory is cleaned 
  def self.stagedUpload 
    include FS

   
    #read in the latest audit - fail on non-null exceptions
    audit = Audit.new(@audit_dir,'cb' )
     
    json = audit.parseLatest 
    if json != nil && audit.hasError(json)
      logger.error "event_id=audit_error:audit=#{json}"
      
      #Do not raise AuditError because it halts entire service
      #Read MAND-613 for more information
      #TODO: MAND-614 - Notification needed for errors in gitchefsync audit file
      #raise AuditError
    end
   
    cookbook_dir = @stage_cb_dir
    
    FS.cmd "mkdir -p #{cookbook_dir}"
    FS.knifeReady(cookbook_dir,@options[:knife_config])
    
    #Check on what is uploaded, knife util creates a list for us
    knifeUtil = KnifeUtil.new(@knife, cookbook_dir)
    listCB = knifeUtil.listCookbooks
    logger.debug "list: #{listCB}"
    stage = @stage_dir + "/*tar.gz"

    Dir.glob(stage).each  do |file|
      logger.debug "event_id=stage_upload:file=#{file}"
      stageCBUpload(file, cookbook_dir, knifeUtil, listCB)
    end
  end

 
  #Extracts and uploads via knife 
  #from the staging directory 
  #don't like that knife or list instance is passed in, for later refactoring
  def self.stageCBUpload(file, cookbook_dir, knifeUtil, listCB, forceUpload = false)
    begin
      logger.info "knife_cookbook_upload:file=#{file}:dest=#{cookbook_dir}"
      match = File.basename(file).match(/(.*)-(\d+\.\d+\.\d+)/)

      if match ==nil || match.length != 3
        logger.error "event_id=invalid_tar:file=#{file}"
        raise InvalidTar, "Invalid tar name #{file}"
      end

      #logger.debug "In chef server? #{knifeUtil.inList(match[1],match[2],listCB)}"
      
     
      if !knifeUtil.inList(match[1],match[2],listCB) || forceUpload
        logger.info "event_id=stage_upload:cookbook=#{match[1]}:ver=#{match[2]}:dir=#{cookbook_dir}"
        FS.cmd "tar -xf #{file} -C #{cookbook_dir}"
        new_cb_list = Array.new       
        cb_dir = Dir.entries(cookbook_dir + "/cookbooks")
        cb_dir.each do |dir|
          
          begin
            cb_info = knifeUtil.parseMetaData(cookbook_dir  + "/cookbooks/" + dir)
            if knifeUtil.inList(cb_info.name(),cb_info.version,listCB)
              logger.debug "event_id=del_cb_in_server:name=#{cb_info}"
              FS.cmdNoError "rm -fr #{cookbook_dir}/cookbooks/#{cb_info.name}"
            else
              #TODO: add this as a concat method in knife_util class
               new_cb_list << cb_info
            end
          rescue NoMetaDataError => e
            logger.debug "no metadata on #{dir}"
          end
        end
        out = FS.cmd "cd #{cookbook_dir} && #{@knife} cookbook upload -a --cookbook-path=#{cookbook_dir}/cookbooks"
        listCB.concat(new_cb_list)
        logger.debug "event_id=stage_upload_output=\n#{out}"
      else
        logger.info"event_id=stage_no_upload:cookbook=#{match[1]}:ver=#{match[2]}"
      end
    rescue CmdError => e
      #logger.error "event_id=cmd_err:#{e.message}"
      
      raise KnifeError.new(e.message)
    rescue InvalidTar => e
      logger.error "event_id=invalid_tar:msg=Continuing on invalid tar"
    ensure
      if File.exists?(cookbook_dir)
        FS.cmd "rm -fr #{cookbook_dir}/*"
      end
    end
   
  end

  def self.init(opts)
   configure(opts)

 end
 
  #Compares git with what is on staging directory
  #WARN: the stage directory should be filled, meaning that cookbooks
  #can be deleted if staging directory is empty
  #verify that we've had at least one successful run, by virtue of the
  #audit file created - that we've had at least one run
  #
  #Does a 2 way compare of the lists in on the chef server
  #and the berks tar packages found in staging directory
  #Adding cookbooks if they aren't found on the server,
  #Deleting cookbooks
  #I don't generate Audit file - move cookbook audit object to module scope
  def self.reconcile

    #Validation
    if Audit.new(@audit_dir, 'cb').latest == nil
      logger.warn "event_id=reconcile_no_audit_detected"
      return
    end

    logger.info "event_id=reconcile:dir=#{@stage_dir}"
    knifeUtil = KnifeUtil.new(@knife, @git_local)
    #Here is what is in the server
    listCB = knifeUtil.listCookbooks

    list_stage = Array.new
    tmp_dir = @stage_cb_dir + "/.tarxf"
    FS.cmd("mkdir -p #{tmp_dir}")

    #Compile what is happening in the stage directory
    stage = @stage_dir + "/*tar.gz"
    Dir.glob(stage).each  do |file|

      begin
        logger.debug "event_id=reconcile_file:file=#{file}"

        FS.cmd "tar -tf #{file} | grep metadata.rb | tar -xf #{file} -C #{tmp_dir}"
        local_list = Array.new
        files  = tmp_dir + "/cookbooks/*/metadata.rb"
        Dir.glob(files) do |metadata|

          cookbook = knifeUtil.parseMetaData(File.expand_path("..",metadata))
          if cookbook !=nil
            list_stage << cookbook
            local_list << cookbook
          end
        end
        #of the local list do we have all of them in chef?
        add_list = knifeUtil.subtract(local_list,listCB)
        logger.debug "local_list #{local_list} delta: #{add_list}"

        self.stageCBUpload(file,@stage_cb_dir,knifeUtil,listCB,true) if !add_list.empty?()
      rescue KnifeError => e
        logger.warn "#{e.message}"
      ensure
        #finally remove what was in the berks tar and in the working tarxf dir
        FS.cmd("rm -fr #{tmp_dir}/*")
      end

    end
    #From the full list of local cookbooks (local_list)
    #we have both sides (what is local) and what is on server
    del_list = knifeUtil.subtract(listCB,list_stage)

    if !del_list.empty?
      logger.warn "event_id=del_cb_pending:cb=#{del_list}"
      del_list.each do |cb|
        logger.debug "deleting: #{cb}"
        #deletion of cookbook - this currently doesn't check node usage
        #so could have deterious side effects
        knifeUtil.delCookbook(cb)
      end
    end
  end
  
end
