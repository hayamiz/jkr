require 'rake'

desc "Preparation before experiments"
task :before

desc "Running experiments"
task :run => FileList['jkr/queue/*.plan'] do
  
end


desc "Wrapping-up data after experiments"
task :after

task :run => [:before]
task :after => [:run]

task :default => [:after]
