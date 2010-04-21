
require 'jkr/utils'
require 'tempfile'

class Jkr
  class Plan
    attr_accessor :title
    attr_accessor :desc
    
    attr_accessor :params
    attr_accessor :vars
  
    # Proc's
    attr_accessor :prep
    attr_accessor :cleanup
    attr_accessor :routine
    attr_accessor :analysis

    attr_accessor :src

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
      @prep = lambda do |_|
        raise NotImplementedError.new("A prep of experiment '#{@title}' is not implemented")
      end
      @cleanup = lambda do |_|
        raise NotImplementedError.new("A cleanup of experiment '#{@title}' is not implemented")
      end

      @src = nil

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
      
      include Jkr::PlanUtils

      def initialize(plan)
        @plan = plan
        @params = nil
      end
      
      def self.load_plan(plan)
        plan_loader = self.new(plan)
        plan.src = File.open(plan.file_path, "r").read
        plan_loader.instance_eval(plan.src, plan.file_path, 1)
        plan
      end
      
      ## Functions for describing plans in '.plan' files below
      def plan
        @plan
      end

      def title(plan_title)
        @plan.title = plan_title.to_s
      end
      
      def description(plan_desc)
        @plan.desc = plan_desc.to_s
      end
      
      def def_parameters(&proc)
        @params = PlanParams.new
        proc.call()
        @plan.params.merge!(@params.params)
        @plan.vars.merge!(@params.vars)
      end
      
      def def_routine(&proc)
        @plan.routine = proc
      end
      def def_prep(&proc)
        @plan.prep = proc
      end
      def def_cleanup(&proc)
        @plan.cleanup = proc
      end
      def def_analysis(&proc)
        @plan.analysis = proc
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
