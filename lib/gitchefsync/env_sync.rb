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

require 'gitchefsync/git_util'
require 'gitchefsync/errors'
require 'gitchefsync/io_util'
require 'gitchefsync/audit'
require 'gitchefsync/config'
require 'gitchefsync/common'
require 'digest'

module Gitchefsync

  def self.included base
    base.extend ClassMethods
  end

  class EnvRepo
    
    attr_reader :git_delta
    
    def initialize(https_url_to_repo)
      options = Gitchefsync.options
      config = Gitchefsync.configuration

      Gitlab.private_token = options[:private_token]
      @https_url_to_repo = https_url_to_repo
      @git_group, @git_project = https_url_to_repo.split(File::SEPARATOR).last(2)
      @stage_filepath = config['stage_dir']
      @stage_target_path = File.join(@stage_filepath, [@git_group, @git_project.chomp(".git")].join('_'))
      @git_default_branch = config['release_branch']
      @git_delta = true
      @git_bin = config['git']
    end

    def sync_repo
      @git_delta = true
      if Git.gitInit(@stage_target_path)
        @git_delta = Gitchefsync.gitDelta(@stage_target_path, @git_default_branch)
        msg = "cd #{@stage_target_path} && #{@git_bin} pull origin #{@git_default_branch}"
        git_pull = lambda { |msg| Git.cmd msg }
        if @git_delta
          git_pull.call(msg)
          Gitchefsync.logger.info "event_id=git_pull_repo_due_to_new_delta:repo=#{@stage_target_path}:git_delta=#{@git_delta}"
        else
          Gitchefsync.logger.info "event_id=skip_git_pull_repo_since_zero_delta:repo=#{@stage_target_path}:git_delta=#{@git_delta}"
        end
      else
        stage_basename = @stage_target_path.split(File::SEPARATOR).last()
        git_clone = Git.cmd "cd #{@stage_filepath} && #{@git_bin} clone #{@https_url_to_repo} #{stage_basename}"
        check_default_branch = Git.cmd "cd #{@stage_target_path} && #{@git_bin} ls-remote origin #{@git_default_branch}"
        Gitchefsync.logger.info "event_id=git_clone_repo_first_time:repo=#{@stage_target_path}:git_default_branch=#{@git_default_branch}"

        #remove EnvRepo project in staging directory if default_branch does not exit
        if check_default_branch.empty?
          Gitchefsync.logger.fatal "event_id=rel_branch_does_not_exist=#{@git_default_branch}"
          Gitchefsync.logger.fatal "event_id=removing_env_repo=#{@https_url_to_repo}, path: #{@stage_target_path}"
          FS.cmd "rm -rf #{@stage_target_path}"
          raise("#{@git_default_branch} does not exist in env_repo: #{@https_url_to_repo}")
        end
      end
    end

    def chef_path
      return File.join(@stage_target_path, "chef-repo")
    end

    def validate_structure
      if !File.directory?(self.chef_path)
        Gitchefsync.logger.fatal "event_id=chef_repo_structure_problem"
        raise("#{self.chef_path} is not a chef-repo path")
      end
    end
  end

  class EnvSync
    def initialize(repo_list)
      options = Gitchefsync.options
      config = Gitchefsync.configuration

      FS.knifeReady(config['stage_dir'],options[:knife_config])

      repo_list.each do |repo|
        repo.validate_structure
      end

      @knife = config['knife']
      @stage_filepath = config['stage_dir']
      @force_upload = config['force_upload']
      @repo_list = repo_list
      #this is a bit of a hack to determine if we're writing audit
      @sous = config['sync_local']
      @audit = Audit.new(config['audit_dir'], 'env' )
      @audit_keep_trim = config['audit_keep_trim']
      @audit_keep_trim ||= 20
      @env_file_list = Array.new()
      @db_file_list = Array.new()
      @role_file_list = Array.new()
    end

    def reject_json content
      file_json = nil
      begin
        
        file_json = JSON.parse content
      rescue Exception => e
        Gitchefsync.logger.error "event_id=env_json_parse_error:file=#{file}"
        @audit.addEnv(file,'UPDATE', e )
      end
      file_json
    end

    def json_type file
      return "env" unless FS.getBasePath(file, "environments").nil?
      return "db" unless FS.getBasePath(file, "data_bags").nil?
      return "role" unless FS.getBasePath(file, "roles").nil?
    end

    def validate_json(f, iden)
      if f['basename'] != f['json'][iden]
        raise ValidationError, "The file json's #{iden} attribute does not match basename: #{f['basename']}"
      end
      Gitchefsync.logger.debug "event_id=json_is_valid:iden=#{iden}:basename=#{f['basename']}"
    end

    def upload_env(f, delta)
      Gitchefsync.logger.debug "event_id=upload_env:filepath=#{f['fullpath']}:delta=#{delta}"
      begin
        validate_json(f, 'name')
        @env_file_list << f['json']['name']
        
        if delta || @force_upload
          FS.cmd "#{@knife} environment from file #{f['fullpath']} --yes"
          Gitchefsync.logger.info "event_id=environment_uploaded:file_json_name=#{f['json']['name']}:file=#{f['fullpath']}"
          @audit.addEnv(f['fullpath'],'UPDATE',nil,f['extra_info'] )
        else
          Gitchefsync.logger.debug "event_id=environment_not_uploaded:file_json_name=#{f['json']['name']}:file=#{f['fullpath']}"
          @audit.addEnv(f['fullpath'],'EXISTING',nil,f['extra_info'] )
        end
      rescue ValidationError => e
        Gitchefsync.logger.error("event_id=validation_error:msg=#{e.message}")
        @audit.addEnv(f['fullpath'],'UPDATE', e ,f['extra_info'])
      end
    end

    def data_bag_iden fullpath
      chef_repo, data_bag = false, false
      fullpath.split(File::SEPARATOR).each do |dir|
        return dir if chef_repo && data_bag
        chef_repo = dir.eql? "chef-repo" unless chef_repo
        data_bag = dir.eql? "data_bags" if chef_repo
      end
      raise ValidationError, "event_id=invalid_path_to_data_bag_json:path=#{fullpath}"
    end

    def upload_db(f, delta)
      Gitchefsync.logger.debug "event_id=upload_data_bag:filepath=#{f['fullpath']}:delta=#{delta}"
      db_iden = data_bag_iden(f['fullpath'])
      begin
        validate_json(f, 'id')
        @db_file_list << [db_iden, f['json']['id']]
        #show_out = FS.cmdNoError "#{@knife} data bag show #{db_iden} #{f['json']['id']}"
        if delta || @force_upload
          FS.cmd "#{@knife} data bag create #{db_iden}"
          FS.cmd "#{@knife} data bag from file #{db_iden} #{f['fullpath']}"
          Gitchefsync.logger.info "event_id=databag_uploaded:file_json_name=#{f['json']['id']}:file=#{f['fullpath']}"
          @audit.addEnv(f['fullpath'],'UPDATE', nil, f['extra_info'] )
        else
          Gitchefsync.logger.debug "event_id=data_bag_not_uploaded:file_json_name=#{f['json']['id']}:file=#{f['fullpath']}"
          @audit.addEnv(f['fullpath'],'EXISTING', nil, f['extra_info'])
        end
      rescue ValidationError => e
        Gitchefsync.logger.error("event_id=validation_error:msg=#{e.message}")
        @audit.addEnv(f['fullpath'],'UPDATE', e , f['extra_info'])
      end
    end

    def upload_role(f, delta)
      Gitchefsync.logger.debug "event_id=upload_role:fullpath=#{f['fullpath']}:delta=#{delta}"
      begin
        validate_json(f, 'name')
        @role_file_list << f['json']['name']
        
        if delta || @force_upload
          FS.cmd "#{@knife} role from file #{f['fullpath']} --yes"
          Gitchefsync.logger.info "event_id=role_uploaded:file_json_name=#{f['json']['name']}:file=#{f['fullpath']}"
          @audit.addEnv(f['fullpath'],'UPDATE',nil, f['extra_info'] )
        else
          Gitchefsync.logger.debug "event_id=role_not_uploaded:file_json_name=#{f['json']['name']}:file=#{f['fullpath']}"
          @audit.addEnv(f['fullpath'],'EXISTING', nil, f['extra_info'] )
        end
      rescue ValidationError => e
        Gitchefsync.logger.error("event_id=validation_error:msg=#{e.message}")
        @audit.addEnv(f['fullpath'],'UPDATE', e , f['extra_info'])
      end
    end

    def cleanup_json_files
      Gitchefsync.logger.info "cleanup_json_files"

      #list env and compare on the server, deleting ones that aren't in git
      knifeUtil = KnifeUtil.new(@knife, @stage_filepath)

      delta_env_list = knifeUtil.listEnv() - @env_file_list
      Gitchefsync.logger.info "event_id=env_diff:delta=#{delta_env_list}"
      # MAND-672
      delta_env_list.each do |env_name|
        # TODO: Audit file may not be correct if someone manually
        #       uploaded an environment file with json 'name' variable different
        #       then actual environment filename.
        a = AuditItem.new(env_name,'',nil)
        a.setAction "DEL"
        FS.cmd "#{@knife} environment delete #{env_name} --yes"
        Gitchefsync.logger.info "event_id=environment_deleted:env_name=#{env_name}"
        @audit.add(a)
      end
     
      delta_db_list = knifeUtil.listDB() - @db_file_list
      Gitchefsync.logger.info "event_id=data_bag_item_diff:delta=#{delta_db_list}"
      delta_db_list.each do |bag, item|
        # TODO: Audit file may not be correct if someone manually
        #       uploaded an data bag with item json 'id' variable different
        #       then actual json filename.
        a = AuditItem.new("BAG: #{bag} ITEM: #{item}",'',nil)
        a.setAction "DEL"
        FS.cmd "#{@knife} data bag delete #{bag} #{item} --yes"
        Gitchefsync.logger.info "event_id=data_bag_item_deleted:bag=#{bag}:item=#{item}"
        @audit.add(a)
        
        items_remaining = knifeUtil.showDBItem(bag)
        if items_remaining.empty?
          a = AuditItem.new("BAG: #{bag}",'',nil)
          a.setAction "DEL"
          FS.cmd "#{@knife} data bag delete #{bag} --yes"
          Gitchefsync.logger.info "event_id=data_bag_deleted:bag=#{bag}"
          @audit.add(a)
        end
      end
 
      delta_role_list = knifeUtil.listRole() - @role_file_list
      Gitchefsync.logger.info "event_id=role_diff:delta=#{delta_role_list}"
      delta_role_list.each do |role_name|
        # TODO: Audit file may not be correct if someone manually
        #       uploaded an role file with json 'name' variable different
        #       then actual role filename.
        a = AuditItem.new(role_name,'',nil)
        a.setAction "DEL"
        FS.cmd "#{@knife} role delete #{role_name} --yes"
        Gitchefsync.logger.info "event_id=role_deleted:role_name=#{role_name}"
        @audit.add(a)
      end

     
      if !@sous
        @audit.write
        #trim the audit file
        @audit.trim(@audit_keep_trim)
      end 
    end

    
    def update_json_files
      Gitchefsync.logger.info "event_id=update_json_files"
      @env_file_list.clear
      @env_file_list << "_default"
      @db_file_list.clear
      @role_file_list.clear

      #latest audit info for delta purposes
      begin
        latest_audit = @audit.latestAuditItems
        latest_audit ||= Array.new
        Gitchefsync.logger.info "event_id=audit_file_found:length=#{latest_audit.length}"
      rescue AuditError => e
        Gitchefsync.logger.warn "event_id=no_audit_file_found"
        latest_audit = Array.new
      end
     
      
      @repo_list.each do |repo|
        env_dir = repo.chef_path + "/**/*json"

        Dir.glob(env_dir).each  do |file|

          file_attr = Hash.new()
          content = File.read(file)
          
          file_attr['json'] = reject_json(content)
          next if file_attr['json'].nil?
          file_attr['type'] = json_type(file)
          file_attr['filename'] = File.basename(file)
          file_attr['basename'] = File.basename(file).chomp(".json")
          file_attr['fullpath'] = file
          file_attr['extra_info'] = Hash.new
          #To do comparison we'll hash current
          file_attr['extra_info']['digest'] = Digest::SHA256.hexdigest content
          #and compare hash to last audit
          item = @audit.itemByName(file,latest_audit)
          delta = true
          if !item.nil?
            Gitchefsync.logger.debug "event_id=audit_item_found:name=#{file}:digest=#{file_attr['extra_info']['digest']}"
            if item.extra_info != nil && file_attr['extra_info']['digest'].eql?(item.extra_info['digest'])
              Gitchefsync.logger.debug "file_digest=#{item.extra_info['digest']}"
              delta = false
            end
          else
            Gitchefsync.logger.warn "event_id=no_audit_item_found:name=#{file}"
          end
          if file_attr['type'].eql? "env"
            upload_env(file_attr, delta)
          elsif file_attr['type'].eql? "db"
            upload_db(file_attr, delta)
          elsif file_attr['type'].eql? "role"
            upload_role(file_attr, delta)
          end
        end
      end

      self.cleanup_json_files
    end
  end

  # sync all environment, data_bags and roles json in repo(s)
  def self.syncEnv
    logger.info "event_id=env_sync_start"

    #TODO: Auto discouver `chef-repo` type repositories known by chefbot
    url = @config['git_env_repo']
    url.gsub!("http://", "https://") if url.start_with? "http://"
    envRepo = EnvRepo.new(https_url_to_repo=url)
    if !@config['sync_local']
      envRepo.sync_repo
    else
      logger.info "event_id=Skip_syncing_env_repos_from_git"
    end

    envSync = EnvSync.new(repo_list=[envRepo])
    logger.info "event_id=start_to_update_json_files"
    envSync.update_json_files
  end

  #Adding functionality to merge environment repos together
  #by introspecting the "working directory" for chef-repo
  #It's been assumed that all repositories have have pulled
  def self.mergeEnvRepos
    include FS,Git

    global_env_path =  @git_local + "/global_chef_env"

    working_dir = Dir.entries(@git_local).reject! {|item| item.start_with?(".") || item.eql?("global_chef_env")}
    working_dir.each  do |dir|
      path = File.join(@git_local, dir)
      chef_repo_dir = path + "/chef-repo"
      if Dir.exists?(chef_repo_dir)
        logger.info("event_id=processing_child_env_repo:dir=#{dir}")
        begin
          #add this repository as a
          Git.cmd "cd #{global_env_path} && #{@git_bin} remote add #{dir} file://#{File.join(path,dir)}"
        rescue Exception => e
          logger.info "event_id=git_remote_already_exists:#{e.message}"
        end
        begin
          #Merge the content via pull
          logger.info"event_id=env_merge:src=#{dir}"
          output  = Git.cmd "cd #{global_env_path} && #{@git_bin} pull #{dir} master"
          logger.info "event_id=env_merge_sucess:msg=#{output}"
        rescue Exception => e
          logger.error "event_id=env:output=#{output}"
          Git.cmd "cd #{global_env_path} && #{@git_bin} reset --hard origin/master"
        end
      end
    end
  end
end
