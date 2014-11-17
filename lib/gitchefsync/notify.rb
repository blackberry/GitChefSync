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

require 'gitchefsync/audit'
require 'gitchefsync/io_util'
require 'net/smtp'

module Gitchefsync
  
  class Notification
    
    def initialize(smtp="mail.rim.net", from="mandolin@blackberry.com",to='mandolin@blackberry.com', msg="")
      @to = to
      @from = from
      @smtp = smtp = Net::SMTP.start(smtp, 25)
      @hostname = FS.cmd "hostname"
    end

    def notifyFromAudit(audit_dir, audit_type)
      audit = Audit.new(audit_dir,audit_type)
      audit_list = audit.latestAuditItems

      audit_list.each do |audit_item|
        if audit_item.ex != nil
          h = audit_item.to_hash
          msg = "From: gichefsync <mandolin@blackberry.com>\nTo: #{h[:maintainer]} #{h[:maintainer_email]}\nSubject: gitchefsync failure\n"
          msg << "Alert from Hostname: #{@hostname}\n\n"
          msg << "Attention!\n\n"
          msg << "gitchefsync has identified you as the maintainer of this artifact\n"
          msg << "====================================\n"
          msg << "#{h[:name]}:#{h[:version]}\n"
          msg << "====================================\n"
          msg << "#{h[:exception]}"

          sendTo(h[:maintainer_email],msg)
          Gitchefsync.logger.info("event_id=email_sent=#{h[:maintainer_email]} ")
        end
      end
      Gitchefsync.logger.info("event_id=notification_complete:audit_type=#{audit_type}")
    end

    def hasDelta(item1,item2)
     
      if item1.nil? || item2.nil?
        return true 
      end
      i1 = item1.to_hash
      i2 = item2.to_hash
     
      if !i1[:extra_info].nil? && !i2[:extra_info].nil?
        
        if !i1[:extra_info]['digest'].nil? && !i1[:extra_info]['digest'].eql?(i2[:extra_info]['digest']) then return true end   
        if !i1[:extra_info]['sha'].nil? && !i1[:extra_info]['sha'].eql?(i2[:extra_info]['sha']) then return true end
      
      end
      return false
    end
    #Aggregates a single email to the "to" email parameter
    def singleNotifyFromAudit(audit_dir,audit_type,to)
      audit = Audit.new(audit_dir,audit_type)
      audit_list = audit.latestAuditItems
      prev_audit = audit.auditItems(-2)
      
      if audit_list.nil?
        Gitchefsync.logger.warn "event_id=unable_to_notify:msg=audit_list_isnull:type=#{audit_type}"
        return
      end
      empty = true
      msg = "From: gitchefsync <mandolin@blackberry.com>\nTo: #{to}\nSubject: gitchefsync failure: summary\n\n"
      msg << "Alert from Hostname: #{@hostname}\n"
      type = "Environment" 
      if audit_type.eql?("cb")
        type = "Cookbooks"
      end
      
      msg << "Notification Type: #{type}\n\n"
      audit_list.each do |audit_item|
        h = audit_item.to_hash
        Gitchefsync.logger.debug "processing item: #{h} ex=#{h[:exception]} #{!h[:exception].nil? && !h[:exception].empty?}"
        
        if !h[:exception].nil? && !h[:exception].empty?
          
          if !prev_audit.nil? && hasDelta(audit_item,audit.itemByNameVersion(h[:name],h[:version],prev_audit))
            Gitchefsync.logger.debug  "item_has_exception=#{h}"
            msg << "item: #{h[:name]}:#{h[:version]} was NOT processed with status #{h[:action]}\n"
            msg << "audit_json= #{h}"
            msg << "ERROR #{h[:exception]}\n\n"
            empty = false
            
          end         
          
        end
        
      end
      
      if !empty
        Gitchefsync.logger.debug  "sending msg=#{msg}"
        sendTo(to,msg) 
      else
        Gitchefsync.logger.info "event_id=no_message_sent"
      end
        
    end

    def send(body)
      @smtp.send_message body, @from, @to
    end

    def sendTo(send_to, body)
      @smtp.send_message body, @from, send_to
    end

    def close
      @smtp.finish
    end
  end
end
