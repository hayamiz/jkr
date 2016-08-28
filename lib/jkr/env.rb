
require 'fileutils'
require 'term/ansicolor'

module Jkr
  class Env
    attr_reader :env_dir
    attr_reader :jkr_dir
    attr_reader :jkr_result_dir
    attr_reader :jkr_plan_dir
    attr_reader :jkr_script_dir
    attr_reader :jkr_queue_dir

    PLAN_DIR = "plan"
    RESULT_DIR = "result"
    SCRIPT_DIR = "script"
    QUEUE_DIR = "queue"

    def initialize(env_dir = Dir.pwd)
      @env_dir = env_dir
      @jkr_dir = File.join(@env_dir, "jkr")
      @jkr_plan_dir = File.join(@jkr_dir, PLAN_DIR)
      @jkr_result_dir = File.join(@jkr_dir, RESULT_DIR)
      @jkr_script_dir = File.join(@jkr_dir, SCRIPT_DIR)
      @jkr_queue_dir = File.join(@jkr_dir, QUEUE_DIR)

      unless Dir.exists?(@jkr_dir)
        raise Errno::ENOENT.new(@jkr_dir)
      end

      [@jkr_dir,
       @jkr_result_dir,
       @jkr_plan_dir,
       @jkr_script_dir,
       @jkr_queue_dir].each do |dir_path|
        unless Dir.exists?(dir_path)
          raise ArgumentError.new("Directory #{dir_path} not found")
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
