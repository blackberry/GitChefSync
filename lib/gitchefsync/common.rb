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


module Gitchefsync

  extend Gitchefsync::Configuration
  def self.included base
    base.extend ClassMethods
  end

  #git installed?
  def self.checkGit
    include Git
    if Git.hasGit == false
      logger.error "event_id=git_error:msg=Git was not found on the path"
      raise GitError, "Git was not detected"
    end
  end

  def self.gitDelta(path, remote_ref)
    include Git
    env_repo = @config['git_env_repo']

    local = Git.cmd "cd #{path} && #{@git_bin} rev-parse HEAD"
    #logger.debug "local #{local}: path=#{path}"
    remote = Git.cmd "cd #{path} && #{@git_bin} ls-remote origin #{remote_ref}"
    return false if remote.empty?
    remote = remote.split(/\s/)[0]

    delta = (local.chomp != remote.chomp)
    logger.debug "event_id=gitDelta:local=#{local.chomp}:remote=#{remote.chomp}:delta=#{delta}"
    delta
  end

  # Verify .gitchefsync at HEAD of default_branch
  def self.checkProjectConfig(cmd, log)
    begin
      proc_cmd, cmd_line = cmd
      return proc_cmd.call(cmd_line)
    rescue GitError, CmdError
      proc_log, msg = log
      proc_log.call(msg)
    end
    return
  end
 
  #@param project - Gitlab project object
  def self.pullProject(project, verify_yml=false)
    
    #MAND-791 skip private repositories
    if !project['public']
      logger.warn "event_id=private_project_detected:project=#{project['path_with_namespace']}"
    end
    p_name = project['path_with_namespace'].split('/').join('_')
    project_path = File.join(@git_local, p_name)

    default_branch =  project['default_branch']

    url_type = @config['gitlab_url_type']
    # "http" is default if @config['gitlab_url_type'] not configured
    url_type ||= "http"

    if url_type.eql?("http")
      project_url = project['http_url_to_repo']
      # Verify .gitchefsync at HEAD of default_branch using `wget -O - url`
      cmd_line = "wget -qO - #{project['web_url']}/raw/#{default_branch}/.gitchefsync.yml"
      cmd = [ Proc.new{ |cmd_line| FS.cmd cmd_line }, cmd_line ]

    elsif url_type.eql?("ssh")
      project_url = project['ssh_url_to_repo']
      # Verify .gitchefsync at HEAD of default_branch using `git archive` (not currently supported/enabled using https protocol)
      cmd_line = "git archive --remote=#{project_url} #{default_branch}: .gitchefsync.yml"
      cmd = [ Proc.new { |cmd_line| Git.cmd("#{cmd_line}") }, cmd_line ]
    end

    msg = "event_id=project_missing_.gitchefsync.yml:project_url=#{project_url}:default_branch=#{default_branch}"
    proc_log = Proc.new { |msg| logger.info "#{msg}" }
    log = [ proc_log, msg ]

    if verify_yml
      check = checkProjectConfig(cmd, log)
      if check.nil? || check.empty?
        proc_log.call(msg)
        return
      end
    end

    begin
      self.updateGit(project_path, project_url)
    rescue GitError => e
      logger.error "event_id=git_error:msg=#{e.message}:trace=#{e.backtrace}"
      logger.error "event_id=remove_project_path: #{project_path}"
      FS.cmd "rm -rf #{project_path}"
    end
  end
 
  #central place to get cookbooks from server
  #will be determined once - and will be (eventually) thread safe
  def self.serverCookbooks
    if @serverCookbooks.nil?
      knifeUtil = KnifeUtil.new(@knife, @git_local)
      @serverCookbooks = knifeUtil.listCookbooks()
    end
    @serverCookbooks
  end

  # Pulls all known projects (determined by configured gitlab-token)
  def self.pullAllProjects
    all_projects = []
    done = false
    page, per_page = 1, 100
    while !done do 
      page_opts = { :per_page => per_page, :page => page}
      repos = Gitlab.projects(page_opts)
      if (repos.length == 0)
        done = true
      else 
        page += 1
      end
      repos.each do |project|
        pullProject(project.to_hash, true)
      end
    end
  end

  # Get subset of known groups (determined by configured gitlab-token)
  def self.getAllGroupIDs(group_names=[], group_ids=[])
    groups = Array.new
    done = false
    page, per_page = 1, 100
    while !done do
      page_opts = { :per_page => per_page, :page => page}
      known_groups = Gitlab.groups(page_opts)
      if (known_groups.length == 0)
        done = true
      else
        page += 1
      end
      known_groups.each do |group|
        name = group.to_hash['name']
        id = group.to_hash['id']
        if (group_names.include? name) || (group_ids.include? id)
          groups << id
        end
      end
    end
    groups.uniq!
    groups
  end

  #TODO: change from git to git with path
  def self.updateGit (project_path, git_path)
    include Git
    begin
      branch = @rel_branch
      logger.debug "using release branch: #{branch}"
      _git = @git_bin
      if !Git.gitInit(project_path)
        FS.cmd "mkdir #{project_path}"
        logger.debug "event_id=git_int:path=#{git_path}:project_path=#{project_path}"
        Git.cmd "cd #{project_path} && #{_git} init"
        Git.cmd "cd #{project_path} && #{_git} remote add origin #{git_path}"
        Git.cmd "cd #{project_path} && #{_git} pull origin #{branch}"
      else
        logger.info "event_id=git_repo_exists:project_path=#{project_path}"
        #wipe tags and re-fetch them
        tags = Git.cmd "cd #{project_path} && git tag"
        arr_tags = tags.split(/\n/)
        arr_tags.each do |tag|
          Git.cmd "cd #{project_path} && git tag -d #{tag}"
        end
      end

      #get all commits and tags
      Git.cmd "cd #{project_path} && #{_git} clean -xdf"
      Git.cmd "cd #{project_path} && #{_git} checkout #{branch}"
      Git.cmd "cd #{project_path} && #{_git} pull origin #{branch}"

      git_tags = Git.cmd "cd #{project_path} && #{_git} fetch --tags"

    rescue CmdError => e
      raise GitError, "An error occurred synchronizing cookbooks #{e.message}"
    end
  end

end
