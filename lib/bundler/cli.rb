# frozen_string_literal: true
require "bundler"
require "bundler/vendored_thor"

module Bundler
  class CLI < Thor
    include Thor::Actions
    AUTO_INSTALL_CMDS = %w(show binstubs outdated exec open console licenses clean).freeze

    def self.start(*)
      super
    rescue Exception => e
      Bundler.ui = UI::Shell.new
      raise e
    end

    def initialize(*args)
      super
      Bundler.reset!

      custom_gemfile = options[:gemfile] || Bundler.settings[:gemfile]
      ENV["BUNDLE_GEMFILE"] = File.expand_path(custom_gemfile) if custom_gemfile && !custom_gemfile.empty?

      Bundler.settings[:retry] = options[:retry] if options[:retry]

      current_cmd = args.last[:current_command].name
      auto_install if AUTO_INSTALL_CMDS.include?(current_cmd)
    rescue UnknownArgumentError => e
      raise InvalidOption, e.message
    ensure
      self.options ||= {}
      Bundler.ui = UI::Shell.new(options)
      Bundler.ui.level = "debug" if options["verbose"]

      if ENV["RUBYGEMS_GEMDEPS"] && !ENV["RUBYGEMS_GEMDEPS"].empty?
        Bundler.ui.warn(
          "The RUBYGEMS_GEMDEPS environment variable is set. This enables RubyGems' " \
          "experimental Gemfile mode, which may conflict with Bundler and cause unexpected errors. " \
          "To remove this warning, unset RUBYGEMS_GEMDEPS.", :wrap => true)
      end
    end

    check_unknown_options!(:except => [:config, :exec])
    stop_on_unknown_option! :exec

    default_task :install
    class_option "no-color", :type => :boolean, :desc => "Disable colorization in output"
    class_option "retry",    :type => :numeric, :aliases => "-r", :banner => "NUM",
                             :desc => "Specify the number of times you wish to attempt network commands"
    class_option "verbose", :type => :boolean, :desc => "Enable verbose output mode", :aliases => "-V"

    def help(cli = nil)
      case cli
      when "gemfile" then command = "gemfile.5"
      when nil       then command = "bundle"
      else command = "bundle-#{cli}"
      end

      manpages = %w(
        bundle
        bundle-config
        bundle-exec
        bundle-gem
        bundle-install
        bundle-package
        bundle-update
        bundle-platform
        gemfile.5)

      if manpages.include?(command)
        root = File.expand_path("../man", __FILE__)

        if Bundler.which("man") && root !~ %r{^file:/.+!/META-INF/jruby.home/.+}
          Kernel.exec "man #{root}/#{command}"
        else
          puts File.read("#{root}/#{command}.txt")
        end
      elsif command_path = Bundler.which("bundler-#{cli}")
        Kernel.exec(command_path, "--help")
      else
        super
      end
    end

    def self.handle_no_command_error(command, has_namespace = $thor_runner)
      if Bundler.settings[:plugins] && Bundler::Plugin.command?(command)
        return Bundler::Plugin.exec_command(command, ARGV[1..-1])
      end

      return super unless command_path = Bundler.which("bundler-#{command}")

      Kernel.exec(command_path, *ARGV[1..-1])
    end

    desc "init [OPTIONS]", "Generates a Gemfile into the current working directory"
    long_desc <<-D
      Init generates a default Gemfile in the current working directory. When adding a
      Gemfile to a gem with a gemspec, the --gemspec option will automatically add each
      dependency listed in the gemspec file to the newly created Gemfile.
    D
    method_option "gemspec", :type => :string, :banner => "Use the specified .gemspec to create the Gemfile"
    def init
      require "bundler/cli/init"
      Init.new(options.dup).run
    end

    desc "check [OPTIONS]", "Checks if the dependencies listed in Gemfile are satisfied by currently installed gems"
    long_desc <<-D
      Check searches the local machine for each of the gems requested in the Gemfile. If
      all gems are found, Bundler prints a success message and exits with a status of 0.
      If not, the first missing gem is listed and Bundler exits status 1.
    D
    method_option "dry-run", :type => :boolean, :default => false, :banner =>
      "Lock the Gemfile"
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "path", :type => :string, :banner =>
      "Specify a different path than the system default ($BUNDLE_PATH or $GEM_HOME). Bundler will remember this value for future installs on this machine"
    map "c" => "check"
    def check
      require "bundler/cli/check"
      Check.new(options).run
    end

    desc "install [OPTIONS]", "Install the current environment to the system"
    long_desc <<-D
      Install will install all of the gems in the current bundle, making them available
      for use. In a freshly checked out repository, this command will give you the same
      gem versions as the last person who updated the Gemfile and ran `bundle update`.

      Passing [DIR] to install (e.g. vendor) will cause the unpacked gems to be installed
      into the [DIR] directory rather than into system gems.

      If the bundle has already been installed, bundler will tell you so and then exit.
    D
    method_option "binstubs", :type => :string, :lazy_default => "bin", :banner =>
      "Generate bin stubs for bundled gems to ./bin"
    method_option "clean", :type => :boolean, :banner =>
      "Run bundle clean automatically after install"
    method_option "deployment", :type => :boolean, :banner =>
      "Install using defaults tuned for deployment environments"
    method_option "frozen", :type => :boolean, :banner =>
      "Do not allow the Gemfile.lock to be updated after this install"
    method_option "full-index", :type => :boolean, :banner =>
      "Fall back to using the single-file index of all gems"
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "jobs", :aliases => "-j", :type => :numeric, :banner =>
      "Specify the number of jobs to run in parallel"
    method_option "local", :type => :boolean, :banner =>
      "Do not attempt to fetch gems remotely and use the gem cache instead"
    method_option "no-cache", :type => :boolean, :banner =>
      "Don't update the existing gem cache."
    method_option "force", :type => :boolean, :banner =>
      "Force downloading every gem."
    method_option "no-prune", :type => :boolean, :banner =>
      "Don't remove stale gems from the cache."
    method_option "path", :type => :string, :banner =>
      "Specify a different path than the system default ($BUNDLE_PATH or $GEM_HOME). Bundler will remember this value for future installs on this machine"
    method_option "quiet", :type => :boolean, :banner =>
      "Only output warnings and errors."
    method_option "shebang", :type => :string, :banner =>
      "Specify a different shebang executable name than the default (usually 'ruby')"
    method_option "standalone", :type => :array, :lazy_default => [], :banner =>
      "Make a bundle that can work without the Bundler runtime"
    method_option "system", :type => :boolean, :banner =>
      "Install to the system location ($BUNDLE_PATH or $GEM_HOME) even if the bundle was previously installed somewhere else for this application"
    method_option "trust-policy", :alias => "P", :type => :string, :banner =>
      "Gem trust policy (like gem install -P). Must be one of " +
        Bundler.rubygems.security_policy_keys.join("|")
    method_option "without", :type => :array, :banner =>
      "Exclude gems that are part of the specified named group."
    method_option "with", :type => :array, :banner =>
      "Include gems that are part of the specified named group."
    map "i" => "install"
    def install
      require "bundler/cli/install"
      no_install = Bundler.settings[:no_install]
      Bundler.settings[:no_install] = false if no_install == true
      Install.new(options.dup).run
    ensure
      Bundler.settings[:no_install] = no_install unless no_install.nil?
    end

    desc "update [OPTIONS]", "update the current environment"
    long_desc <<-D
      Update will install the newest versions of the gems listed in the Gemfile. Use
      update when you have changed the Gemfile, or if you want to get the newest
      possible versions of the gems in the bundle.
    D
    method_option "full-index", :type => :boolean, :banner =>
      "Fall back to using the single-file index of all gems"
    method_option "group", :aliases => "-g", :type => :array, :banner =>
      "Update a specific group"
    method_option "jobs", :aliases => "-j", :type => :numeric, :banner =>
      "Specify the number of jobs to run in parallel"
    method_option "local", :type => :boolean, :banner =>
      "Do not attempt to fetch gems remotely and use the gem cache instead"
    method_option "quiet", :type => :boolean, :banner =>
      "Only output warnings and errors."
    method_option "source", :type => :array, :banner =>
      "Update a specific source (and all gems associated with it)"
    method_option "force", :type => :boolean, :banner =>
      "Force downloading every gem."
    method_option "ruby", :type => :boolean, :banner =>
      "Update ruby specified in Gemfile.lock"
    method_option "bundler", :type => :string, :lazy_default => "> 0.a", :banner =>
      "Update the locked version of bundler"
    def update(*gems)
      require "bundler/cli/update"
      Update.new(options, gems).run
    end

    desc "show GEM [OPTIONS]", "Shows all gems that are part of the bundle, or the path to a given gem"
    long_desc <<-D
      Show lists the names and versions of all gems that are required by your Gemfile.
      Calling show with [GEM] will list the exact location of that gem on your machine.
    D
    method_option "paths", :type => :boolean,
                           :banner => "List the paths of all gems that are required by your Gemfile."
    method_option "outdated", :type => :boolean,
                              :banner => "Show verbose output including whether gems are outdated."
    def show(gem_name = nil)
      require "bundler/cli/show"
      Show.new(options, gem_name).run
    end
    map %w(list) => "show"

    desc "binstubs GEM [OPTIONS]", "Install the binstubs of the listed gem"
    long_desc <<-D
      Generate binstubs for executables in [GEM]. Binstubs are put into bin,
      or the --binstubs directory if one has been set. Calling binstubs with [GEM [GEM]]
      will create binstubs for all given gems.
    D
    method_option "force", :type => :boolean, :default => false, :banner =>
      "Overwrite existing binstubs if they exist"
    method_option "path", :type => :string, :lazy_default => "bin", :banner =>
      "Binstub destination directory (default bin)"
    method_option "standalone", :type => :array, :lazy_default => [], :banner =>
      "Make binstubs that can work without the Bundler runtime"
    def binstubs(*gems)
      require "bundler/cli/binstubs"
      Binstubs.new(options, gems).run
    end

    desc "outdated GEM [OPTIONS]", "list installed gems with newer versions available"
    long_desc <<-D
      Outdated lists the names and versions of gems that have a newer version available
      in the given source. Calling outdated with [GEM [GEM]] will only check for newer
      versions of the given gems. Prerelease gems are ignored by default. If your gems
      are up to date, Bundler will exit with a status of 0. Otherwise, it will exit 1.
    D
    method_option "local", :type => :boolean, :banner =>
      "Do not attempt to fetch gems remotely and use the gem cache instead"
    method_option "pre", :type => :boolean, :banner => "Check for newer pre-release gems"
    method_option "source", :type => :array, :banner => "Check against a specific source"
    method_option "strict", :type => :boolean, :banner =>
      "Only list newer versions allowed by your Gemfile requirements"
    method_option "major", :type => :boolean, :banner => "Only list major newer versions"
    method_option "minor", :type => :boolean, :banner => "Only list minor newer versions"
    method_option "patch", :type => :boolean, :banner => "Only list patch newer versions"
    method_option "parseable", :aliases => "--porcelain", :type => :boolean, :banner =>
      "Use minimal formatting for more parseable output"
    def outdated(*gems)
      require "bundler/cli/outdated"
      Outdated.new(options, gems).run
    end

    desc "cache [OPTIONS]", "Cache all the gems to vendor/cache", :hide => true
    method_option "all",  :type => :boolean, :banner => "Include all sources (including path and git)."
    method_option "all-platforms", :type => :boolean, :banner => "Include gems for all platforms present in the lockfile, not only the current one"
    method_option "no-prune", :type => :boolean, :banner => "Don't remove stale gems from the cache."
    def cache
      require "bundler/cli/cache"
      Cache.new(options).run
    end

    desc "package [OPTIONS]", "Locks and then caches all of the gems into vendor/cache"
    method_option "all",  :type => :boolean, :banner => "Include all sources (including path and git)."
    method_option "all-platforms", :type => :boolean, :banner => "Include gems for all platforms present in the lockfile, not only the current one"
    method_option "cache-path", :type => :string, :banner =>
      "Specify a different cache path than the default (vendor/cache)."
    method_option "gemfile", :type => :string, :banner => "Use the specified gemfile instead of Gemfile"
    method_option "no-install", :type => :boolean, :banner => "Don't install the gems, only the package."
    method_option "no-prune", :type => :boolean, :banner => "Don't remove stale gems from the cache."
    method_option "path", :type => :string, :banner =>
      "Specify a different path than the system default ($BUNDLE_PATH or $GEM_HOME). Bundler will remember this value for future installs on this machine"
    method_option "quiet", :type => :boolean, :banner => "Only output warnings and errors."
    method_option "frozen", :type => :boolean, :banner =>
      "Do not allow the Gemfile.lock to be updated after this package operation's install"
    long_desc <<-D
      The package command will copy the .gem files for every gem in the bundle into the
      directory ./vendor/cache. If you then check that directory into your source
      control repository, others who check out your source will be able to install the
      bundle without having to download any additional gems.
    D
    def package
      require "bundler/cli/package"
      Package.new(options).run
    end
    map %w(pack) => :package

    desc "exec [OPTIONS]", "Run the command in context of the bundle"
    method_option :keep_file_descriptors, :type => :boolean, :default => false
    long_desc <<-D
      Exec runs a command, providing it access to the gems in the bundle. While using
      bundle exec you can require and call the bundled gems as if they were installed
      into the system wide Rubygems repository.
    D
    map "e" => "exec"
    def exec(*args)
      require "bundler/cli/exec"
      Exec.new(options, args).run
    end

    desc "config NAME [VALUE]", "retrieve or set a configuration value"
    long_desc <<-D
      Retrieves or sets a configuration value. If only one parameter is provided, retrieve the value. If two parameters are provided, replace the
      existing value with the newly provided one.

      By default, setting a configuration value sets it for all projects
      on the machine.

      If a global setting is superceded by local configuration, this command
      will show the current value, as well as any superceded values and
      where they were specified.
    D
    def config(*args)
      require "bundler/cli/config"
      Config.new(options, args, self).run
    end

    desc "open GEM", "Opens the source directory of the given bundled gem"
    def open(name)
      require "bundler/cli/open"
      Open.new(options, name).run
    end

    desc "console [GROUP]", "Opens an IRB session with the bundle pre-loaded"
    def console(group = nil)
      require "bundler/cli/console"
      Console.new(options, group).run
    end

    desc "version", "Prints the bundler's version information"
    def version
      Bundler.ui.info "Bundler version #{Bundler::VERSION}"
    end
    map %w(-v --version) => :version

    desc "licenses", "Prints the license of all gems in the bundle"
    def licenses
      Bundler.load.specs.sort_by {|s| s.license.to_s }.reverse_each do |s|
        gem_name = s.name
        license  = s.license || s.licenses

        if license.empty?
          Bundler.ui.warn "#{gem_name}: Unknown"
        else
          Bundler.ui.info "#{gem_name}: #{license}"
        end
      end
    end

    desc "viz [OPTIONS]", "Generates a visual dependency graph"
    long_desc <<-D
      Viz generates a PNG file of the current Gemfile as a dependency graph.
      Viz requires the ruby-graphviz gem (and its dependencies).
      The associated gems must also be installed via 'bundle install'.
    D
    method_option :file, :type => :string, :default => "gem_graph", :aliases => "-f", :desc => "The name to use for the generated file. see format option"
    method_option :format, :type => :string, :default => "png", :aliases => "-F", :desc => "This is output format option. Supported format is png, jpg, svg, dot ..."
    method_option :requirements, :type => :boolean, :default => false, :aliases => "-R", :desc => "Set to show the version of each required dependency."
    method_option :version, :type => :boolean, :default => false, :aliases => "-v", :desc => "Set to show each gem version."
    method_option :without, :type => :array, :default => [], :aliases => "-W", :banner => "GROUP[ GROUP...]", :desc => "Exclude gems that are part of the specified named group."
    def viz
      require "bundler/cli/viz"
      Viz.new(options.dup).run
    end

    desc "gem GEM [OPTIONS]", "Creates a skeleton for creating a rubygem"
    method_option :exe, :type => :boolean, :default => false, :aliases => ["--bin", "-b"], :desc => "Generate a binary executable for your library."
    method_option :coc, :type => :boolean, :desc => "Generate a code of conduct file. Set a default with `bundle config gem.coc true`."
    method_option :edit, :type => :string, :aliases => "-e", :required => false, :banner => "EDITOR",
                         :lazy_default => [ENV["BUNDLER_EDITOR"], ENV["VISUAL"], ENV["EDITOR"]].find {|e| !e.nil? && !e.empty? },
                         :desc => "Open generated gemspec in the specified editor (defaults to $EDITOR or $BUNDLER_EDITOR)"
    method_option :ext, :type => :boolean, :default => false, :desc => "Generate the boilerplate for C extension code"
    method_option :mit, :type => :boolean, :desc => "Generate an MIT license file. Set a default with `bundle config gem.mit true`."
    method_option :test, :type => :string, :lazy_default => "rspec", :aliases => "-t", :banner => "rspec",
                         :desc => "Generate a test directory for your library, either rspec or minitest. Set a default with `bundle config gem.test rspec`."
    def gem(name)
      require "bundler/cli/gem"
      Gem.new(options, name, self).run
    end

    def self.source_root
      File.expand_path(File.join(File.dirname(__FILE__), "templates"))
    end

    desc "clean [OPTIONS]", "Cleans up unused gems in your bundler directory"
    method_option "dry-run", :type => :boolean, :default => false, :banner =>
      "Only print out changes, do not clean gems"
    method_option "force", :type => :boolean, :default => false, :banner =>
      "Forces clean even if --path is not set"
    def clean
      require "bundler/cli/clean"
      Clean.new(options.dup).run
    end

    desc "platform [OPTIONS]", "Displays platform compatibility information"
    method_option "ruby", :type => :boolean, :default => false, :banner =>
      "only display ruby related platform information"
    def platform
      require "bundler/cli/platform"
      Platform.new(options).run
    end

    desc "inject GEM VERSION ...", "Add the named gem(s), with version requirements, to the resolved Gemfile"
    def inject(name, version, *gems)
      require "bundler/cli/inject"
      Inject.new(options, name, version, gems).run
    end

    desc "lock", "Creates a lockfile without installing"
    method_option "update", :type => :array, :lazy_default => [], :banner =>
      "ignore the existing lockfile, update all gems by default, or update list of given gems"
    method_option "local", :type => :boolean, :default => false, :banner =>
      "do not attempt to fetch remote gemspecs and use the local gem cache only"
    method_option "print", :type => :boolean, :default => false, :banner =>
      "print the lockfile to STDOUT instead of writing to the file system"
    method_option "lockfile", :type => :string, :default => nil, :banner =>
      "the path the lockfile should be written to"
    method_option "full-index", :type => :boolean, :default => false, :banner =>
      "Fall back to using the single-file index of all gems"
    method_option "add-platform", :type => :array, :default => [], :banner =>
      "add a new platform to the lockfile"
    def lock
      require "bundler/cli/lock"
      Lock.new(options).run
    end

    desc "env", "Print information about the environment Bundler is running under"
    def env
      Env.new.write($stdout)
    end

    desc "add GEM [VERSION]", "Add the named gem to the bottom of Gemfile"
    def add(name, version = nil)
      require "bundler/cli/add"
      Add.new(name, version).run
    end

    if Bundler.settings[:plugins]
      require "bundler/cli/plugin"
      desc "plugin SUBCOMMAND ...ARGS", "manage the bundler plugins"
      subcommand "plugin", Plugin
    end

    # Reformat the arguments passed to bundle that include a --help flag
    # into the corresponding `bundle help #{command}` call
    def self.reformatted_help_args(args)
      bundler_commands = all_commands.keys
      help_flags = %w(--help -h)
      exec_commands = %w(e ex exe exec)
      help_used = args.index {|a| help_flags.include? a }
      exec_used = args.index {|a| exec_commands.include? a }
      command = args.find {|a| bundler_commands.include? a }
      if exec_used && help_used
        if exec_used + help_used == 1
          %w(help exec)
        else
          args
        end
      elsif command.nil?
        abort("Could not find command \"#{args.join(" ")}\".")
      else
        ["help", command || args].flatten.compact
      end
    end

  private

    # Automatically invoke `bundle install` and resume if
    # Bundler.settings[:auto_install] exists. This is set through config cmd
    # `bundle config auto_install 1`.
    #
    # Note that this method `nil`s out the global Definition object, so it
    # should be called first, before you instantiate anything like an
    # `Installer` that'll keep a reference to the old one instead.
    def auto_install
      return unless Bundler.settings[:auto_install]

      begin
        Bundler.definition.specs
      rescue GemNotFound
        Bundler.ui.info "Automatically installing missing gems."
        Bundler.reset!
        invoke :install, []
        Bundler.reset!
      end
    end
  end
end
