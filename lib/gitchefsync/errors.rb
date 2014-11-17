
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

  class KnifeError < CmdError; end

  class NoMetaDataError < KnifeError; end

  class InvalidTar < Error; end

  class AuditError < Error;  end

  class NoGitGroups < Error; end

  class ValidationError < Error; end

  class ConfigError < Error; end
end
