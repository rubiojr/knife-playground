require 'chef'

module KnifePlayground

  class PgConfigSettings < Chef::Knife

    banner "knife pg config settings"

    deps do 
      require 'colorize'
    end

    def run
      Chef::Config.configure do |h|
        h.each do |k,v|
          puts "#{k.to_s.ljust(30).cyan} #{v}"
        end
      end
    end

  end

  class PgClientnodeDelete < Chef::Knife
    banner "knife pg clientnode delete CLIENT"

    deps do
      require 'chef/node'
      require 'chef/api_client'
      require 'chef/json_compat'
    end

    def run
      @client_name = @name_args[0]
      if @client_name.nil?
        show_usage
        ui.fatal("You must specify a client name")
        exit 1
      end
      ui.info "Deleting CLIENT #{@client_name}..."
      delete_object(Chef::ApiClient, @client_name)

      @node_name = @name_args[0]
      if @node_name.nil?
        show_usage
        ui.fatal("You must specify a node name")
        exit 1
      end
      ui.info "Deleting NODE #{@node_name}..."
      delete_object(Chef::Node, @node_name)

    end
    
    #
    # Most of this code comes from Opscode Knife cookbook_upload.rb plugin:
    #
    # https://github.com/opscode/chef/blob/master/chef/lib/chef/knife/cookbook_upload.rb
    #
    # Minor modifications to add Git support added
    #
    class PgGitCookbookUpload < Chef::Knife

      CHECKSUM = "checksum"
      MATCH_CHECKSUM = /[0-9a-f]{32,}/

      deps do
        require 'chef/exceptions'
        require 'chef/cookbook_loader'
        require 'chef/cookbook_uploader'
        require 'git'
      end

      banner "knife pg git cookbook upload [COOKBOOKS...] (options)"

      option :cookbook_path,
        :short => "-o PATH:PATH",
        :long => "--cookbook-path PATH:PATH",
        :description => "A colon-separated path to look for cookbooks in",
        :proc => lambda { |o| o.split(":") }

      option :freeze,
        :long => '--freeze',
        :description => 'Freeze this version of the cookbook so that it cannot be overwritten',
        :boolean => true

      option :all,
        :short => "-a",
        :long => "--all",
        :description => "Upload all cookbooks, rather than just a single cookbook"

      option :force,
        :long => '--force',
        :boolean => true,
        :description => "Update cookbook versions even if they have been frozen"

      option :environment,
        :short => '-E',
        :long  => '--environment ENVIRONMENT',
        :description => "Set ENVIRONMENT's version dependency match the version you're uploading.",
        :default => nil

      option :depends,
        :short => "-d",
        :long => "--include-dependencies",
        :description => "Also upload cookbook dependencies"

      def run
        git_urls = @name_args.dup
        git_urls.each do |n| 
          if n =~ /^git:\/\//
            @name_args.delete n
            git_repo = n
            git_clone(git_repo)
          end
        end
        
        config[:cookbook_path] ||= Chef::Config[:cookbook_path]

        assert_environment_valid!
        version_constraints_to_update = {}
        # Get a list of cookbooks and their versions from the server
        # for checking existence of dependending cookbooks.
        @server_side_cookbooks = Chef::CookbookVersion.list

        if config[:all]
          justify_width = cookbook_repo.cookbook_names.map {|name| name.size}.max.to_i + 2
          cookbook_repo.each do |cookbook_name, cookbook|
            cookbook.freeze_version if config[:freeze]
            upload(cookbook, justify_width)
            version_constraints_to_update[cookbook_name] = cookbook.version
          end
        else
          if @name_args.empty?
            show_usage
            ui.error("You must specify the --all flag or at least one cookbook name")
            exit 1
          end
          justify_width = @name_args.map {|name| name.size }.max.to_i + 2
          @name_args.each do |cookbook_name|
            begin
              cookbook = cookbook_repo[cookbook_name]
              if config[:depends]
                cookbook.metadata.dependencies.each do |dep, versions|
                  @name_args.push dep
                end
              end
              cookbook.freeze_version if config[:freeze]
              upload(cookbook, justify_width)
              version_constraints_to_update[cookbook_name] = cookbook.version
            rescue Chef::Exceptions::CookbookNotFoundInRepo => e
              ui.error("Could not find cookbook #{cookbook_name} in your cookbook path, skipping it")
              Chef::Log.debug(e)
            end
          end
        end

        ui.info "upload complete"
        update_version_constraints(version_constraints_to_update) if config[:environment]
      end

      def cookbook_repo
        @cookbook_loader ||= begin
          Chef::Cookbook::FileVendor.on_create { |manifest| Chef::Cookbook::FileSystemFileVendor.new(manifest, config[:cookbook_path]) }
          Chef::CookbookLoader.new(config[:cookbook_path])
        end
      end

      def update_version_constraints(new_version_constraints)
        new_version_constraints.each do |cookbook_name, version|
          environment.cookbook_versions[cookbook_name] = "= #{version}"
        end
        environment.save
      end


      def environment
        @environment ||= config[:environment] ? Environment.load(config[:environment]) : nil
      end

      private
      
      def git_clone(url, opts = {})
        repo = File.basename(URI.parse(url).path.split('/').last, '.git')
        @name_args << repo
        cbpath = Chef::Config[:cookbook_path].first rescue '/var/chef/cookbooks'
        path = File.join(cbpath.first, repo)
        # Error if previous checkout exist
        if File.directory?(path + '/.git')
          ui.info "Cookbook #{repo} already downloaded."
        else
          ui.info "Downloading cookbook from #{url}"
          Git.clone url, path, opts
        end
      end

      def assert_environment_valid!
        environment
      rescue Net::HTTPServerException => e
        if e.response.code.to_s == "404"
          ui.error "The environment #{config[:environment]} does not exist on the server, aborting."
          Log.debug(e)
          exit 1
        else
          raise
        end
      end

      def upload(cookbook, justify_width)
        ui.info("Uploading #{cookbook.name.to_s.ljust(justify_width + 10)} [#{cookbook.version}]")

        check_for_broken_links(cookbook)
        check_dependencies(cookbook)
        Chef::CookbookUploader.new(cookbook, config[:cookbook_path], :force => config[:force]).upload_cookbook
      rescue Net::HTTPServerException => e
        case e.response.code
        when "409"
          ui.error "Version #{cookbook.version} of cookbook #{cookbook.name} is frozen. Use --force to override."
          Log.debug(e)
        else
          raise
        end
      end

      # if only you people wouldn't put broken symlinks in your cookbooks in
      # the first place. ;)
      def check_for_broken_links(cookbook)
        # MUST!! dup the cookbook version object--it memoizes its
        # manifest object, but the manifest becomes invalid when you
        # regenerate the metadata
        broken_files = cookbook.dup.manifest_records_by_path.select do |path, info|
          info[CHECKSUM].nil? || info[CHECKSUM] !~ MATCH_CHECKSUM
        end
        unless broken_files.empty?
          broken_filenames = Array(broken_files).map {|path, info| path}
          ui.error "The cookbook #{cookbook.name} has one or more broken files"
          ui.info "This is probably caused by broken symlinks in the cookbook directory"
          ui.info "The broken file(s) are: #{broken_filenames.join(' ')}"
          exit 1
        end
      end

      def check_dependencies(cookbook)
        # for each dependency, check if the version is on the server, or
        # the version is in the cookbooks being uploaded. If not, exit and warn the user.
        cookbook.metadata.dependencies.each do |cookbook_name, version|
          unless check_server_side_cookbooks(cookbook_name, version) || check_uploading_cookbooks(cookbook_name, version)
            # warn the user and exit
            ui.error "Cookbook #{cookbook.name} depends on cookbook #{cookbook_name} version #{version},"
            ui.error "which is not currently being uploaded and cannot be found on the server."
            exit 1
          end
        end
      end

      def check_server_side_cookbooks(cookbook_name, version)
        if @server_side_cookbooks[cookbook_name].nil?
          false
        else
          @server_side_cookbooks[cookbook_name]["versions"].each do |versions_hash|
            return true if Chef::VersionConstraint.new(version).include?(versions_hash["version"])
          end
          false
        end
      end

      def check_uploading_cookbooks(cookbook_name, version)
        if config[:all]
          # check from all local cookbooks in the path
          unless cookbook_repo[cookbook_name].nil?
            return Chef::VersionConstraint.new(version).include?(cookbook_repo[cookbook_name].version)
          end
        else
          # check from only those in the command argument
          if @name_args.include?(cookbook_name)
            return Chef::VersionConstraint.new(version).include?(cookbook_repo[cookbook_name].version)
          end
        end
        false
      end

    end
  end
end
