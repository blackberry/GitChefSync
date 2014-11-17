# GitChefSync

This is a Git -> Chef synchronization toolset.

### Requirements:
- Git (1.8.x)
- Chef
- Berkshelf

### Gem dependencies:
- gitlab + transitive dependencies


To install (from source):
- git clone [Mandolin GitChefSync](http://gitlab.rim.net/chef/gitchefsync.git)
- cd gitchefsync && rake install

### Running:

- Typical "Master" options are:
- Cookbook sync: gitchefsync syncCookbooks\[Local\] -c /path_to_config -t xxxyyy
- Environment sync: gitchefsync syncEnv -c /path_to_config -t xxxyyy
- "Sous" operation:
- stage upload: gitchefsync stagedUpload -c /path_to_config -t xxxyyy


### Configurtion
- VM configuration of gitchefsync [chefsync](https://gitlab.rim.net/mand-common/chefsync)
- sync-config.json is the central config file as is required for all operations
- relies on knife and chef in general it's best to create a .chef directory in the working directory and fill it with appropriate values, if not a .chef directory and it's corresponding knife.rb file will be created
- The script relies on 3 important pieces: Git, Chef and Berks.  Installation options: see chefsync (https://gitlab.rim.net/mand-common/chefsync).
- There are 2 modes of operation: pulling from master node in git and pushing those changes into chef server, OR using the working directory (which is a git repository).  Running locally can be achieved with the "sync_local flag".
- syncCookbooks still however depends on berks upload, which for all intents and purposes requires access to both git and the internet for getting and installing cookbook dependencies.

### Sample sync-config.json

    {
        "knife":"/usr/local/bin/knife",
        "git":"/usr/bin/git",
        "berks":"/usr/local/bin/berks",
        "working_directory":"/working_directory",
        "knife_file":"path_to_knife/knife.rb",
        "gitlab_group_names": [MAND_IEMS,MAND_BBM],
        "git_env_repo": ""https://gitlab.rim.net/mand-common/global_chef_env.git",
        "cookbook_repo_list" : ["https://gitlab.rim.net/mand-ems/iems.git"],
        "sync_local" : true,
        "stage_dir": "path_to_stage_",
        "tmp_dir" : "path_to_store_tmp_data"
    }

### Dependencies:
- Berks: likely requires you to disable SSL if running through a proxy
- Git - goes without saying, need git
- Gitlab - https://gitlab.rim.net is hardcoded currently
- knife.rb file

Example of knife.rb : 
node_name                'admin'
client_key               '/etc/chef-server/admin.pem'
chef_server_url          'https://yourserver'

### Cookbook synchronization
- the current "gitlab_group_names" are the gitlab groups that are the target set of repositories for synchronization
- this can work concurrently with "cookbook_repo_list" an explicit set of git urls for those cookbooks 
- cookbooks are vetted with berks and knife
- requires appropriate knife configuration
- requires that your gitlab token is set correctly
	
### Environment synchronization

- the "git_env_group" is the repository that houses the standard configuration for environment, data bags and roles
- chef-repo
	- environments/
		env.json
	- data_bags/
		- db_name1/
			databag.json
		- db_name2/
	-roles/

OR structure:

- chef-repo
	- env_identifier1/
		- environments/
			env.json
		- data_bags/
			- db_name1/
				databag.json
			- db_name2/
		-roles/
	-env_identifier2/
		- environments/
			env.json
		- data_bags/
			- db_name1/
				databag.json
			- db_name2/
		-roles/

See (http://gitlab.rim.net/mand-common/global_chef_env) for example of such

### Audit
- An audit file will be generated for each run of the synchronization, where each cookbook will generate a json structure of which cookbooks were deployed or staged
- 2 sets of audit files will be generated, one for the cookbook related synchronization and another for 
- Audit will be in a parsable json format stored in the staging directory  
    [
        {
            "name": "epagent",
            "ts": 1400702312,
            "version": "1.0.3"
        },
        {
            "name": "epagent",
            "ts": 1400702315,
            "version": "1.0.4"
        },
        
        {
            "name": "bb_jboss-cookbook",
            "ts": 1400702327,
            "version": "1.0.0"
        },
        {
            "name": "relay_node-cookbook",
            "ts": 1400702329,
            "exception": "Some Exception msg",
            "version": "1.0.0"
        },
        {
            "name": "bb_jssecert-cookbook",
            "ts": 1400702333,
            "version": "1.0.0"
        },
        {
            "name": "nsupdate",
            "ts": 1400702336,
            "version": "1.0.0"
        },
        {
            "name": "jdk-certicom",
            "ts": 1400702339
        },
        {
            "name": "bb_apt-cookbook",
            "ts": 1400702343,
            "version": "1.0.0"
        }
        
    ]
