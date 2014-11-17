require 'open3'
require 'gitchefsync/errors'
# raise an excetpion here

module Gitchefsync
  module FS

    #copy the knife file over
    #TODO: do this the ruby way
    def self.knifeReady (working_dir,knife_file)
      chef_dir = working_dir + "/" + ".chef"
      if !File.exists?(chef_dir)
        self.cmd "mkdir -p #{chef_dir}"
      end
      if !File.exists?(knife_file)
        raise(KnifeError, "knife file must be defined")
      end

      self.cmd "cp -f #{knife_file} #{chef_dir}/knife.rb"
      #check for knife readiness
      self.cmd "cd #{working_dir} && knife client list"
    end

    #executes a command line process
    #raises and exception on stderr
    #returns the sys output
    def self.cmd(x, env={})
      ret = nil
      err = nil
      Open3.popen3(env, x) do |stdin, stdout, stderr, wait_thr|
        ret = stdout.read
        err = stderr.read
      end
      if err.to_s != ''
        raise CmdError, "stdout=#{err}:cmd=#{x}"
      end
      ret
    end

    #there is a host of errors associated with berks
    #"DEPRECATED: Your Berksfile contains a site location ..."
    #this method is to allow filtering on the message to determine
    #what is a real error versus what is just a warning - at this time
    #will just have no checking
    def self.cmdBerks(x)
      self.cmdNoError(x)
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

    def self.flatten(path, find)
      arr_path = Array.new
      arr_path.unshift(File.basename(path, ".*"))
      fp = path
      while true do
        fp = File.expand_path("..", fp)
        return nil if fp == "/"
        break if File.basename(fp) == find
        arr_path.unshift(File.basename(fp))
      end
      arr_path.join("_")
    end

    def self.getBasePath(path, find)
      fp = path
      while true do
        fp = File.expand_path("..", fp)
        return nil if fp == "/"
        return fp if File.basename(fp) == find
      end
    end
  end
end
