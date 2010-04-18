
require 'jkr/plan-utils'

class Jkr
  VERSION = '0.0.1'

  class JkrEnv
    attr_reader :jkr_dir
    attr_reader :working_dir
    
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

  class JkrPlan
    attr_accessor :title
    attr_accessor :desc
    
    attr_accessor :params
    attr_accessor :vars
    attr_accessor :routine

    attr_reader :file_path

    def initialize(jkr_env, plan_file_path = nil)
      @jkr_env = jkr_env
      @file_path = plan_file_path || jkr_env.next_plan
      return nil unless @file_path

      @title = "no title"
      @desc = "no desc"

      @params = {}
      @vars = {}
      @routine = lambda do |_|
        raise NotImplementedError.new("A routine of experiment '#{@title}' is not implemented")
      end

      PlanLoader.load_plan(self)
    end


    class PlanLoader
      class PlanParams
        attr_reader :vars
        attr_reader :params

        def initialize()
          @vars = {}
          @params = {}
        end
        
        def [](key)
          @params[key]
        end

        def []=(key, val)
          @params[key] = val
        end
      end
      
      def initialize(plan)
        @plan = plan
        @params = nil
      end
      
      def self.load_plan(plan)
        plan_loader = self.new(plan)
        plan_src = File.open(plan.file_path, "r").read
        plan_loader.instance_eval(plan_src, plan.file_path, 0)
        plan
      end
      
      ## Functions for describing plans in '.plan' files below
      def title(plan_title)
        @plan.title = plan_title.to_s
      end
      
      def description(plan_desc)
        @plan.desc = plan_desc.to_s
      end
      
      def def_parameters(&proc)
        @params = PlanParams.new
        proc.call(self)
        @plan.params.merge!(@params.params)
        @plan.vars.merge!(@params.vars)
      end
      
      def def_routine(&proc)
        @routine = proc
      end
      
      def parameter(arg = nil)
        if arg.is_a? Hash
          # set param
          @params.params.merge!(arg)
        else
          @params
        end
      end

      def variable(arg = nil)
        if arg.is_a? Hash
          @params.vars.merge!(arg)
        else
          @params
        end
      end
    end
  end
end
