
class Jkr
  class Env
    attr_reader :jkr_dir
    attr_reader :working_dir
    attr_reader :jkr_result_dir
    attr_reader :jkr_plan_dir
    
    PLAN_DIR = "plan"
    RESULT_DIR = "result"

    def initialize(working_dir = Dir.pwd, jkr_dir = File.join(Dir.pwd, "jkr"))
      @jkr_dir = jkr_dir
      @working_dir = working_dir
      @jkr_plan_dir = File.join(@jkr_dir, PLAN_DIR)
      @jkr_result_dir = File.join(@jkr_dir, RESULT_DIR)
      
      [@jkr_dir, @jkr_result_dir, @jkr_plan_dir].each do |dir_path|
        unless Dir.exists?(dir_path)
          raise RuntimeError.new("#{dir_path} doesn't exist!")
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
