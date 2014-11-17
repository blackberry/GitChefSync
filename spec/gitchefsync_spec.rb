require 'rspec'
require 'gitchefsync'
require 'gitchefsync/opts'
require 'gitlab'

class DummyClass 
  extend Gitchefsync
  def self.included base
      base.extend ClassMethods
   end
  
end

#
#
describe "gitchefsync" do
  
	before(:each) do
	  puts "before"
    
    
    Gitlab.endpoint = 'https://gitlab.rim.net/api/v3'
    @args = args "sync-config.json"
	 
    @opts = Gitchefsync.parseAndConfigure(@args)
    
    #make the staging directory - TODO possibly to this in main code
    `mkdir -p #{@opts[:config]['stage_dir']}`
	end

  after :each do
    puts "Clean up..."
    
  end
     
  #requires git lab private token to be in environment 
  def args (configLoc)
    conf = File.dirname(__FILE__) + "/#{configLoc}"
    args = Array.new
    args << "--private_token=#{ENV['TOKEN']}"
    args << "--config=#{conf}"
    return args
  end
  
	it "should be Configuration" do
	  #Gitchefsync.is_a Gitchefsync::Configuration
	  puts Gitchefsync.ancestors()
	  
	end
	
  it "should process environment" do
    
      puts "parse #{@ARGS}"
      #@dummy_class.parseAndConfigure( nil )
          
      Gitchefsync.syncEnv 
    end
	
   
  it "should sync cookbooks" do
    
    Gitchefsync.syncCookbooks()
    
  end
  
  it "should stage cookbooks" do
    
    Gitchefsync.stagedUpload()
  end
  
  it "should work with no git group" do
    Gitchefsync.parseAndConfigure( args("config-nogitgroup.json") )
    Gitchefsync.syncCookbooks()
  end
  
  it "should be idempotent" do
    
  end
  
  it "should log syslog" do
    arg = args("sync-config.json")
    arg << "--syslog"
    opts = Gitchefsync.parseAndConfigure( arg )
    
    
  end
  
end

