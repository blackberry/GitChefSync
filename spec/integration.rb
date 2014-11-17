require 'gitchefsync'
require 'gitlab'


class WrapSync
  extend Gitchefsync
  
end

#
#ALL specs are failing because of inheritence to all base method
describe Gitchefsync do
	 
	
	 before :each do
	  @sync =  WrapSync.new
	 	puts "before..."
	 	@config = File.dirname(__FILE__) + "/sync-config.json"
	 	@ARGS = Array.new
		@ARGS << "--private_token=#{ENV['TOKEN']}"
		@ARGS << "--config=#{@config}"
		Gitlab.endpoint = 'https://gitlab.rim.net/api/v3'
		
		Gitchefsync.checkGit 
	 	
	 	@options = Gitchefsync.parseAndConfigure( @ARGS )
	 	
	 end
	 
	 after :each do
	 	puts "Clean up..."
	 end


	
		it "parsing success" do
			config = File.dirname(__FILE__) + "/../bin/sync-config.json"
			
			ARGS = Array.new
			ARGS << "--private_token=xxxyyyzzz"
			ARGS << "--config=#{config}"
			
			options = Gitchefsync.parseAndConfigure( ARGS )

			options[:private_token].should == "xxxyyyzzz"
		end 
		
		it "parsing failure" do
		  begin
		    options = Gitchefsync.parseAndConfigure( ARGS )
		  rescue Exception => e
		    puts "#{e.message}"
		  end
		  
		end
	
	
    
		it "syncing" do
      puts(" sync ARGS: #{@ARGS}")
      Gitchefsync.parseAndConfigure( @ARGS )
			Gitchefsync::Env.sync
			
	
	 end
	

end