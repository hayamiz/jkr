
require 'jkr/utils'
require 'tempfile'

class Jkr
  class Plan
    attr_accessor :title
    attr_accessor :desc
    attr_accessor :short_desc
    
    attr_accessor :params
    attr_accessor :vars

    attr_accessor :resultset_dir

    # Proc's
    attr_accessor :prep
    attr_accessor :cleanup
    attr_accessor :routine
    attr_accessor :routine_nr_run
    attr_accessor :analysis
    attr_accessor :param_filters

    attr_accessor :src

    attr_reader :file_path
    attr_reader :jkr_env

    def initialize(jkr_env, plan_name, options = {})
      @jkr_env = jkr_env
      @file_path = File.expand_path("#{plan_name}.plan", @jkr_env.jkr_plan_dir)
      if options[:plan_path]
        @file_path = options[:plan_path]
      else
        if ! plan_name
          raise ArgumentError.new("plan_name is required.")
        end
      end

      if ! File.exists?(@file_path)
        raise Errno::ENOENT.new(@file_path)
      end

      @title = "no title"
      @desc = "no desc"
      @short_desc = nil

      @params = {}
      @vars = {}
      @routine = lambda do |_|
        raise NotImplementedError.new("A routine of experiment '#{@title}' is not implemented")
      end
      @routine_nr_run = 1
      @prep = lambda do |_|
        raise NotImplementedError.new("A prep of experiment '#{@title}' is not implemented")
      end
      @cleanup = lambda do |_|
        raise NotImplementedError.new("A cleanup of experiment '#{@title}' is not implemented")
      end
      @param_filters = []

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

      def short_desc(short_desc)
        @plan.short_desc = short_desc.gsub(/ /, '_').gsub(/\//, '!')
      end
      
      def def_parameters(&proc)
        @params = PlanParams.new
        proc.call()
        @plan.params.merge!(@params.params)
        @plan.vars.merge!(@params.vars)
      end
      
      def def_routine(options = {}, &proc)
        if options[:nr_run]
          @plan.routine_nr_run = options[:nr_run]
        end
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
          $stderr.puts("'parameter' is deprecated. use 'constant' instead.")
          @params.params.merge!(arg)
        else
          @params
        end
      end

      def constant(arg = nil)
        if arg.is_a? Hash
          # set param
          @params.params.merge!(arg)
        else
          raise ArgumentError.new
        end
      end


      def variable(arg = nil)
        if arg.is_a? Hash
          @params.vars.merge!(arg)
        else
          @params
        end
      end

      def param_filter(&proc)
        @plan.param_filters.push(proc)
      end
    end
  end
end
