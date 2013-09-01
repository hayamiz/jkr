
require 'jkr/utils'
require 'jkr/error'
require 'tempfile'

class Jkr
  class Plan
    attr_accessor :title
    attr_accessor :desc
    attr_accessor :short_desc

    attr_accessor :params
    attr_accessor :vars

    attr_accessor :base_plan
    attr_accessor :plan_search_path

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
      @base_plan = nil
      @jkr_env = jkr_env

      if options[:plan_search_path].is_a? String
        options[:plan_search_path] = [options[:plan_search_path]]
      end
      @plan_search_path = [@jkr_env.jkr_plan_dir]
      if options[:plan_search_path]
        @plan_search_path = options[:plan_search_path] + @plan_search_path
      end

      if options[:plan_path]
        @file_path = options[:plan_path]
      else
        if ! plan_name
          raise ArgumentError.new("plan_name is required.")
        end

        plan_candidates = @plan_search_path.map do |dir|
          File.expand_path("#{plan_name}.plan", dir)
        end

        @file_path = plan_candidates.find do |path|
          File.exists?(path)
        end

        if ! @file_path
          raise ArgumentError.new("No such plan: #{plan_name}")
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

    def param_names
      @params.keys
    end

    def var_names
      @vars.keys
    end

    def do_prep(plan = self)
      if self.base_plan
        self.base_plan.do_prep(plan)
      end
      self.prep.call(plan)
    end

    def do_routine(plan, params)
      if self.base_plan
        self.base_plan.do_routine(plan, params)
      end
      self.routine.call(plan, params)
    end

    def do_cleanup(plan = self)
      if self.base_plan
        self.base_plan.do_cleanup(plan)
      end
      self.cleanup.call(plan)
    end

    def do_analysis(plan = self)
      if self.base_plan
        self.base_plan.do_analysis(plan)
      end
      self.analysis.call(plan)
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

      def extend(base_plan_name)
        base_plan = Plan.new(self.plan.jkr_env, base_plan_name.to_s,
                             :plan_search_path => @plan.plan_search_path)
        self.plan.base_plan = base_plan

        @plan.params.merge!(base_plan.params)
        @plan.vars.merge!(base_plan.vars)
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

        consts = @params.params
        vars   = @params.vars

        if @plan.base_plan
          consts.keys.each do |const|
            if ! @plan.params.include?(const)
              raise Jkr::ParameterError.new("#{const} is not defined in base plan: #{@plan.base_plan.title}")
            end
          end

          vars.keys.each do |var|
            if ! @plan.vars.include?(var)
              raise Jkr::ParameterError.new("#{var} is not defined in base plan: #{@plan.base_plan.title}")
            end
          end
        end

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
          constant(arg)
        else
          @params
        end
      end

      def constant(arg = nil)
        if arg.is_a? Hash
          arg.keys.each do |const_name|
            if @params.vars.keys.include?(const_name)
              raise Jkr::ParameterError.new("#{const_name} is already defined as variable")
            end
          end

          # set param
          @params.params.merge!(arg)
        else
          raise ArgumentError.new
        end
      end


      def variable(arg = nil)
        if arg.is_a? Hash
          arg.keys.each do |var_name|
            if @params.params.keys.include?(var_name)
              raise Jkr::ParameterError.new("#{var_name} is already defined as constant")
            end
          end

          @params.vars.merge!(arg)
        else
          raise ArgumentError.new
        end
      end

      def param_filter(&proc)
        @plan.param_filters.push(proc)
      end
    end
  end
end
