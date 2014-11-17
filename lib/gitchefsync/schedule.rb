require 'timeout'

module Gitchefsync
  class ScheduleSync
    
    def initialize()
      options = Gitchefsync.options
      config = Gitchefsync.configuration
      
      @lock_filename = config['lock_filename'] || 'sync.lock'
      @lock_timeout = config['lock_timeout'] || 10
      @lock_timeout = @lock_timeout.to_i
      
      @master_sync_timeout = config['master_sync_timeout'] || 600
      @master_sync_timeout = @master_sync_timeout.to_i
            
      @sous_rsync_user = config['sous_rsync_user'] || 'chefsync'
      @sous_rsync_host = config['sous_rsync_host'] || ''
      @sous_rsync_src = config['sous_rsync_src'] || config['stage_dir'] || '/opt/gitchefsync/staging/'
      @sous_rsync_dest = config['sous_rsync_dest'] || 
                         File.join(File::SEPARATOR, config['stage_dir'].split(File::SEPARATOR)[1..-2]) || 
                         '/opt/gitchefsync/'
      @sous_rsync_options = config['sous_rsync_options'] || '-ar --delete'
      @sous_rsync_excludes = config['sous_rsync_excludes'] || '.chef .snapshot'
      
      @sous_sync_timeout = config['sous_sync_timeout'] || 600
      @sous_sync_timeout = @sous_sync_timeout.to_i 
    end
        
    def obtainExclusiveLock 
      Gitchefsync.logger.info "event_id=attempt_to_lock_file:lock_filename=#{@lock_filename}"
      lock_file = File.open(@lock_filename, File::RDWR|File::CREAT, 0644)
  
      begin
        Timeout::timeout(@lock_timeout) { lock_file.flock(File::LOCK_EX) }
      rescue
        Gitchefsync.logger.fatal "event_id=unable_to_lock_file:lock_filename=#{@lock_filename}"
        exit 1
      end
      
      lock_file
    end
  
    def master
      lock_file = obtainExclusiveLock
      
      begin
        Timeout::timeout(@master_sync_timeout) do
          Gitchefsync.logger.info "event_id=master_sync_starting"
  
          #Setup and check Gitlab API endpoint
          Gitlab.endpoint = 'http://gitlab.rim.net/api/v3'
          Gitchefsync.checkGit
  
          Gitchefsync.syncEnv
          Gitchefsync.syncCookbooks
          Gitchefsync.reconcile
          cleanTmp()
          Gitchefsync.logger.info "event_id=master_sync_completed"
          
          # MAND-615 - This file will signal its ok for this directory to be sous sync target
          File.write(File.join(@sous_rsync_src, "master_sync_completed"), "")
        end
      rescue Timeout::Error
        Gitchefsync.logger.fatal "event_id=master_sync_timed_out:master_sync_timeout=#{@master_sync_timeout}"
        exit 1
      rescue => e
        Gitchefsync.logger.error "event_id=caught_exception:msg=#{e.message}"
      end
      lock_file.close
    end
  
    def sous
      lock_file = obtainExclusiveLock
      
      begin
        Timeout::timeout(@sous_sync_timeout) do
          Gitchefsync.logger.info "event_id=sous_sync_starting"
          
          exclude = ""
          @sous_rsync_excludes.split(" ").each do |pattern|
            exclude = "#{exclude} --exclude #{pattern}"
          end
          
          if @sous_rsync_host.empty?
            Gitchefsync.logger.fatal "event_id=sous_rsync_host_not_configured"
            exit 1
          end
          
          master_sync_completed = File.join(@sous_rsync_src, "master_sync_completed")
          master_sync_completed_cmd = "ssh #{@sous_rsync_user}@#{@sous_rsync_host} ls #{master_sync_completed} 2>/dev/null"
          Gitchefsync.logger.info "event_id=check_master_sync_completed:cmd=#{master_sync_completed_cmd}"
          master_sync_completed_stdout = FS.cmd "#{master_sync_completed_cmd}"
          
          # MAND-615 - Do not perform an rsync on #{master_sync_completed} target if empty.
          # Avoid doing rsync command and staged cookbook/env upload in situation where master 
          # chef server was re-instantiated and master sync has yet to run once.
          if master_sync_completed_stdout.empty?
            Gitchefsync.logger.fatal "event_id=missing_master_sync_completed_file:master_sync_completed=#{master_sync_completed}"
            exit 1
          end
            
          rsync_cmd = "rsync #{@sous_rsync_options} #{exclude} #{@sous_rsync_user}@#{@sous_rsync_host}:#{@sous_rsync_src} #{@sous_rsync_dest} 2>/dev/null"
          Gitchefsync.logger.info "event_id=execute_rsync:cmd=#{rsync_cmd}"
          FS.cmd "#{rsync_cmd}"
  
          Gitchefsync.stagedUpload
          Gitchefsync.syncEnv
          Gitchefsync.reconcile
          cleanTmp()
          Gitchefsync.logger.info "event_id=sous_sync_completed"
        end
      rescue Timeout::Error
        Gitchefsync.logger.fatal "event_id=sous_sync_timed_out:sous_sync_timeout=#{@sous_sync_timeout}"
        exit 1
      rescue => e
        Gitchefsync.logger.error "event_id=caught_exception:msg=#{e.message}"
      end
      lock_file.close
    end
  
    #Due to ridley bug (4.0.0+ possibly earlier) -clean the tmp directories
    #takes current "Date" and cleans up
    def cleanTmp
      ts_str = "/tmp/d" + Date.today.strftime("%Y%m%d") + "-*"
      Gitchefsync.logger.info "clean up of #{ts_str}"
      FS.cmdNoError "sudo rm -fr #{ts_str}"
    end
  end
  
  def self.runMasterSync
    scheduleSync = ScheduleSync.new()
    scheduleSync.master
  end
    
  def self.runSousSync
    #force loocal sync
    options[:config]['sync_local'] = "true"
      
    #Make sure sous sync only runs on the primary node
    drbd_connection_state = FS.cmd("sudo drbdadm cstate chef_disk", 
        { "TERM" => "xterm", "PATH" => "/usr/sbin:/usr/bin:/bin:/sbin" })
    drbd_role = FS.cmd("sudo drbdadm role chef_disk", 
        { "TERM" => "xterm", "PATH" => "/usr/sbin:/usr/bin:/bin:/sbin" })
    
    drbd_connection_state.delete!("\n")
    drbd_role.delete!("\n")
    
    connected = drbd_connection_state.match(/Connected/)
    role = drbd_role.match(/^Primary/)
    
    if connected and role
      Gitchefsync.logger.info "event_id=proceed_to_sous_sync:drbd_connection_state=#{connected}:drbd_role=#{role}"
      scheduleSync = ScheduleSync.new()
      scheduleSync.sous
    elsif   
      Gitchefsync.logger.fatal "event_id=abort_sous_sync:drbd_connection_state=#{connected}:drbd_role=#{role}"
      exit 1
    end
  end
end
