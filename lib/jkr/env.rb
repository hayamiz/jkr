
require 'fileutils'

class Jkr
  class Env
    attr_reader :jkr_dir
    attr_reader :working_dir
    attr_reader :jkr_result_dir
    attr_reader :jkr_plan_dir
    attr_reader :jkr_script_dir
    
    PLAN_DIR = "plan"
    RESULT_DIR = "result"
    SCRIPT_DIR = "script"

    def initialize(working_dir = Dir.pwd, jkr_dir = File.join(Dir.pwd, "jkr"))
      @jkr_dir = jkr_dir
      @working_dir = working_dir
      @jkr_plan_dir = File.join(@jkr_dir, PLAN_DIR)
      @jkr_result_dir = File.join(@jkr_dir, RESULT_DIR)
      @jkr_script_dir = File.join(@jkr_dir, SCRIPT_DIR)
      
      [@jkr_dir, @jkr_result_dir, @jkr_plan_dir, @jkr_script_dir].each do |dir_path|
        unless Dir.exists?(dir_path)
          FileUtils.mkdir_p(dir_path)
        end
      end
    end

    def next_plan
      self.plans.first
    end

    def plans
      Dir.glob("#{@jkr_plan_dir}#{File::SEPARATOR}*.plan").sort
    end
  end
end
