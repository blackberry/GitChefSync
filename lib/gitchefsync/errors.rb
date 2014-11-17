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

#Define custom exception classes here
module Gitchefsync

  # Custom error class for rescuing from all Gitlab errors.
  class Error < StandardError; end

  # command, system error
  class CmdError < Error; end

  #A Git error has occurred
  #or "fatal/error condition"
  class GitError < Error; end

  #A knife cookbook is frozen error
  class FrozenError < CmdError; end

  class BerksError < CmdError; end

  class NoBerksError < BerksError; end
    
  class BerksLockError < BerksError; end

  class KnifeError < CmdError; end

  class NoMetaDataError < KnifeError; end

  class InvalidTar < Error; end

  class AuditError < Error;  end

  class NoGitGroups < Error; end

  class ValidationError < Error; end

  class ConfigError < Error; end
end
