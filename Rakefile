require 'rubygems'
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.version = File.exist?('VERSION') ? File.read('VERSION') : ""
  gem.name = "knife-playground"
  gem.homepage = "http://github.com/rubiojr/knife-playground"
  gem.license = "MIT"
  gem.summary = %Q{Opscode Knife plugin with useful tools}
  gem.description = %Q{Misc tools for Opscode Chef Knife}
  gem.email = "rubiojr@frameos.org"
  gem.authors = ["Sergio Rubio"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  gem.add_runtime_dependency 'chef', '>= 0.10'
  gem.add_runtime_dependency 'git'
  gem.add_runtime_dependency 'colorize'
  #  gem.add_development_dependency 'rspec', '> 1.2.3'
end
Jeweler::RubygemsDotOrgTasks.new

task :default => :build

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "Knife Playground #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
