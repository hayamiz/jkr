
module Jkr
  class PlanFinder
    def initialize(jkr_env)
      @jkr_env = jkr_env
    end

    def find_by_name(name, options = {})
      options[:plan_search_path] ||= [@jkr_env.jkr_plan_dir]

      options[:plan_search_path].each do |dir|
        Dir.glob("#{dir}/*.plan").each do |path|
          if File.basename(path, ".plan") == name
            return path
          end
        end
      end

      nil
    end

    def find_by_result_id(ret_id)
      ret_dir = Dir[sprintf("#{@jkr_env.jkr_result_dir}/%05d*", ret_id)].first

      unless ret_dir
        raise ArgumentError.new("Result not found: id=#{ret_id}")
      end

      plan_files = Dir["#{ret_dir}/*.plan"]

      if plan_files.size < 1
        raise RuntimeError.new("No plan file found: #{File.basename(ret_dir)}")
      elsif plan_files.size > 1
        raise RuntimeError.new("Multiple plan files found: #{File.basename(ret_dir)}")
      end

      plan_files.first
    end
  end
end
