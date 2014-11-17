module Gitchefsync
  module Log
    #Wrapped sys log Logger
    #Overload all the logger methods - although substitution is not covered
    class SysLogger

      #TODO: may define syslog open at this point
      def initialize(name)
        begin
          Syslog.open(name, Syslog::LOG_PID, Syslog::LOG_LOCAL1)
        rescue Exception => e
          puts "Syslog error: #{e.message}"
        end

      end

      def debug(*args)
        log(Syslog::LOG_DEBUG,args[0])
      end

      def info(*args)
        log(Syslog::LOG_INFO,args[0])
      end

      def warn(*args)
        log(Syslog::LOG_WARNING,args[0])
      end

      def error(*args)
        log(Syslog::LOG_ERR,args[0])
      end

      def fatal(*args)
        log(Syslog::LOG_EMERG,args[0])
      end

      def log ( level, msg)
        begin
          Syslog.log(level, msg)
        ensure
          #Syslog.close
        end
      end
    end
  end
end
