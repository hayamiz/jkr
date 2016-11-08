
require 'fileutils'
require 'term/ansicolor'

module Jkr
  class Env
    attr_reader :env_dir
    attr_reader :jkr_dir
    attr_reader :jkr_result_dir
    attr_reader :jkr_plan_dir
    attr_reader :jkr_script_dir

    PLAN_DIR = "plan"
    RESULT_DIR = "result"
    SCRIPT_DIR = "script"

    def initialize(env_dir = Dir.pwd)
      @env_dir = env_dir
      @jkr_dir = File.join(@env_dir, "jkr")
      @jkr_plan_dir = File.join(@jkr_dir, PLAN_DIR)
      @jkr_result_dir = File.join(@jkr_dir, RESULT_DIR)
      @jkr_script_dir = File.join(@jkr_dir, SCRIPT_DIR)

      unless Dir.exists?(@env_dir)
        raise Errno::ENOENT.new(@jkr_dir)
      end

      [@jkr_dir,
       @jkr_result_dir,
       @jkr_plan_dir,
       @jkr_script_dir].each do |dir_path|
        unless Dir.exists?(dir_path)
          raise ArgumentError.new("Directory #{dir_path} not found")
        end
      end
    end

    def self.valid_env_dir?(dir)
      jkr_dir = File.expand_path("jkr", dir)
      plan_dir = File.expand_path("plan", jkr_dir)
      script_dir = File.expand_path("script", jkr_dir)
      result_dir = File.expand_path("result", jkr_dir)

      [jkr_dir, result_dir, plan_dir, script_dir].each do |dir_|
        unless Dir.exists?(dir_)
          return false
        end
      end

      true
    end

    # Find Jkr env dir if 'dir' is under an valid Jkr environemnt directory.
    def self.find(dir)
      dir = File.expand_path("./", dir)
      while true
        if valid_env_dir?(dir)
          return dir
        end

        parent_dir = File.expand_path("../", dir)
        if parent_dir == dir
          break
        else
          dir = parent_dir
        end
      end

      nil
    end

    # Find an executed Jkr result if 'dir' is under the result dir, and return result id.
    # return nil otherwise.
    def self.find_result(dir)
      dir = File.expand_path("./", dir)
      while true
        parent_dir = File.expand_path("../", dir)
        gp_dir = File.expand_path("../../", dir) # grand parent
        ggp_dir = File.expand_path("../../../", dir) # grand grand parent

        if ggp_dir == gp_dir
          return nil
        end

        if valid_env_dir?(ggp_dir)
          if File.basename(gp_dir) == "jkr" &&
              File.basename(parent_dir) == "result" &&
              File.basename(dir) =~ /^[0-9]+/
            return File.basename(dir).to_i
          end
        end

        dir = File.expand_path("../", dir)
      end
    end
  end
end
