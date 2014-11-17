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

    #Aggregates a single email to the "to" email parameter
    def singleNotifyFromAudit(audit_dir,audit_type,to)
      audit = Audit.new(audit_dir,audit_type)
      audit_list = audit.latestAuditItems
      msg = "From: gichefsync <mandolin@blackberry.com>\nTo: #{to}\nSubject: gitchefsync failure: summary\n\n"
      msg << "Alert from Hostname: #{@hostname}\n\n"
      audit_list.each do |audit_item|
        h = audit_item.to_hash

        if h[:exception] != nil
          ver = ""
          if !h[:version].empty? then ver = ":" + h[:version] end

          msg << "item: #{h[:name]}#{ver} was NOT processed with status #{h[:action]} "
          msg << "\nERROR #{h[:exception]}"
        else
          msg << "item: #{h[:name]} was NOT processed with status #{h[:action]} "
        end
        msg << "\n\n"
      end
      sendTo(to,msg)
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
