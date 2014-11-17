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
