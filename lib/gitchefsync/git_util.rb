require 'gitchefsync/config'
require 'gitlab'
#Git helper module
module Gitchefsync
  module Git

    def self.hasGit()
      begin
        git_ver = `git --version`
        return git_ver.match('git version .*')
      rescue
        #TODO
        raise NoGit, "Git must be installed"
      end
    end

    #check that path exists and git is intializated
    def self.gitInit (path)
      return File.directory?(path + "/.git")
    end

    #a check to determine if a repository exists
    #this is inherintly dangerous operation, as network issues could
    #prevent the real issue
    #will provide a 2 stage check, one a pull (if successful) return true
    #second, if that failts
    def self.remoteExists(path, remote)
      Gitchefsync.logger.debug "event_id=checkRemoteExists:path=#{path}"
      begin
        self.cmd("cd #{path} && git ls-remote")
        return true
      rescue GitError => e
        Gitchefsync.logger.warn "event_id=git_pull_err:msg=#{e.message}"
      end
      # we've passed the first
      begin
        #arbitrary gitlab command
        Gitlab.users()
        #successfully called Gitlab and not been able to pull remotely: give up
        return false
      rescue Exception => e
        #in the face of not being able to contact Gitlab (for whatever reason) assume repository alive
        return true
      end
      return true
    end

    #Return all git tags (which map to a SHA-1 hash) that only exist on monitoring branch (@rel_branch)
    #Solves MAND-602 "ChefSync - Tagged Cookbooks on non-targeted git branches get synced"
    def self.branchTags(path, branch)
      self.cmd "cd #{path} && git clean -xdf"

      self.cmd "cd #{path} && git checkout #{branch}"
      git_graph = "git log --graph --oneline --branches=master --pretty='%H'"
      branch_tags = "#{git_graph} | grep '^*' |" +
      " tr -d '|' | awk '{ print $2 }' |" +
      " xargs -n1 git describe --tags --exact-match 2>/dev/null"

      status = `cd #{path} && git status`.split(/\n/)
      graph = `cd #{path} &&  #{git_graph}`.split(/\n/)
      Gitchefsync.logger.debug "event_id=branchTags: path=#{path}, status=#{status}"
      Gitchefsync.logger.debug "event_id=branchTags: path=#{path}, graph=#{graph}"

      tags = self.cmd("cd #{path} && #{branch_tags}").split(/\n/)
      Gitchefsync.logger.info "event_id=branchTags: path=#{path}, tags=#{tags}"
      tags
    end

    #executes a command line process
    #raises and exception on stderr
    #returns the sys output
    def self.cmd(x)
      ret = nil
      err = nil
      Open3.popen3(x) do |stdin, stdout, stderr, wait_thr|
        ret = stdout.read
        err = stderr.read
      end
      ret << err

      if ret.start_with?"error:"
        raise GitError, "stderr=#{ret}:cmd=#{x}"
      end
      if ret.start_with?"fatal:"
        raise GitError, "stderr=#{ret}:cmd=#{x}"
      end
      ret
    end

    def self.cmdNoError(x)
      ret = nil
      err = nil
      Open3.popen3(x) do |stdin, stdout, stderr, wait_thr|
        ret = stdout.read
        err = stderr.read
      end

      ret << err
      ret
    end
  end
end
