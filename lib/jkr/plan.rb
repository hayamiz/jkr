
require 'jkr/utils'
require 'jkr/error'
require 'tempfile'
require 'net/http'
require 'fileutils'

module Jkr
  class Plan
    attr_accessor :title
    attr_accessor :desc
    attr_accessor :short_desc
    attr_accessor :plan_name

    attr_accessor :params
    attr_accessor :vars
    attr_accessor :metastore

    attr_accessor :base_plan
    attr_accessor :plan_search_path
    attr_accessor :script_search_path
    attr_accessor :used_scripts

    attr_accessor :resultset_dir

    # Proc's
    attr_accessor :prep
    attr_accessor :cleanup
    attr_accessor :routine
    attr_accessor :routine_nr_run
    attr_accessor :analysis
    attr_accessor :param_filters
    attr_accessor :exec_time_estimate

    attr_accessor :src

    attr_accessor :file_path
    attr_reader :jkr_env

    private_class_method :new
    def initialize(jkr_env)
      @base_plan = nil
      @used_scripts = []
      @jkr_env = jkr_env
      @metastore = Hash.new

      @title = "no title"
      @desc = "no desc"
      @short_desc = nil
      @plan_name = plan_name

      @params = {}
      @vars = {}
      @routine = nil
      @routine_nr_run = 1
      @prep = nil
      @cleanup = nil
      @param_filters = []

      @src = nil
    end

    def self.create_by_name(jkr_env, plan_name, options = {})
      plan = new(jkr_env)

      if options[:plan_search_path]
        plan.plan_search_path = options[:plan_search_path]
      else
        plan.plan_search_path = [plan.jkr_env.jkr_plan_dir]
      end

      if options[:script_search_path]
        plan.script_search_path = options[:script_search_path]
      else
        plan.script_search_path = [plan.jkr_env.jkr_script_dir]
      end

      finder = PlanFinder.new(jkr_env)
      plan.file_path = finder.find_by_name(plan_name,
                                           :plan_search_path => plan.plan_search_path)
      unless plan.file_path
        raise ArgumentError.new("No such plan: #{plan_name}")
      end

      PlanLoader.load_plan(plan)

      plan
    end

    def self.create_by_result_id(jkr_env, ret_id, options = {})
      plan = new(jkr_env)
      finder = PlanFinder.new(jkr_env)
      plan.file_path = finder.find_by_result_id(ret_id)

      plan.plan_search_path = [File.expand_path("../plan", plan.file_path)]
      plan.script_search_path = [File.expand_path("../script", plan.file_path),
                                 plan.jkr_env.jkr_script_dir]

      unless plan.file_path
        raise ArgumentError.new("Not valid result ID: #{ret_id}")
      end

      resultset_num = sprintf "%05d", ret_id
      dirs = Dir.glob(File.join(plan.jkr_env.jkr_result_dir, resultset_num)+"*")
      if dirs.size == 0
        raise RuntimeError.new("Resultset not found: #{ret_id}")
      elsif dirs.size > 1
        raise RuntimeError.new("Cannot identify result set directory")
      end
      plan.resultset_dir = dirs.first

      PlanLoader.load_plan(plan)

      plan
    end

    def param_names
      @params.keys
    end

    def var_names
      @vars.keys
    end

    def do_prep(plan = self)
      if self.prep.nil?
        self.base_plan.do_prep(plan)
      else
        self.prep.call(plan)
      end
    end

    def do_routine(plan, params)
      if self.routine.nil?
        self.base_plan.do_routine(plan, params)
      else
        self.routine.call(plan, params)
      end
    end

    def do_cleanup(plan = self)
      if self.cleanup.nil?
        self.base_plan.do_cleanup(plan)
      else
        self.cleanup.call(plan)
      end
    end

    def do_analysis(plan = self)
      if self.analysis.nil?
        self.base_plan.resultset_dir = self.resultset_dir
        self.base_plan.do_analysis(plan)
      else
        Jkr::AnalysisUtils.define_analysis_utils(resultset_dir, self)
        ret = self.analysis.call(plan)
        Jkr::AnalysisUtils.undef_analysis_utils(self)

        ret
      end
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
        plan.src = File.open(plan.file_path, "r").read
        plan_loader.instance_eval(plan.src, plan.file_path, 1)
        plan
      end

      ## Functions for describing plans in '.plan' files below
      def plan
        @plan
      end

      def use_script(name, use = true)
        # find script file
        if name.is_a? Symbol
          name = name.to_s + ".rb"
        elsif ! (name =~ /\.rb$/)
          name += ".rb"
        end

        path = nil
        search_dirs = @plan.script_search_path
        while ! search_dirs.empty?
          dir = search_dirs.shift
          path = File.expand_path(name, dir)

          if File.exists?(path)
            break
          end
        end

        if path
          load path
          if use
            @plan.used_scripts.push(path)
          end
        else
          raise RuntimeError.new("Cannot use script: #{name}")
        end
      end

      def load_script(name)
        use_script(name, false)
      end

      def extend(base_plan_name)
        base_plan = Plan.create_by_name(self.plan.jkr_env, base_plan_name.to_s,
                                        :plan_search_path => @plan.plan_search_path,
                                        :script_search_path => @plan.script_search_path)
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

      # call routine of super plan
      def super_routine(plan, params)
        if @plan.base_plan == nil
          RuntimeError.new("No super plan.")
        else
          @plan.base_plan.do_routine(plan, params)
        end
      end

      def super_prep(plan)
        if @plan.base_plan == nil
          RuntimeError.new("No super plan.")
        else
          @plan.base_plan.do_prep(plan)
        end
      end

      def super_cleanup(plan)
        if @plan.base_plan == nil
          RuntimeError.new("No super plan.")
        else
          @plan.base_plan.do_cleanup(plan)
        end
      end

      def super_analysis(plan)
        if @plan.base_plan == nil
          RuntimeError.new("No super plan.")
        else
          @plan.base_plan.resultset_dir = @plan.resultset_dir
          @plan.base_plan.do_analysis(plan)
        end
      end

      def exec_time_estimate(&proc)
        @plan.exec_time_estimate = proc
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

      def jkr_env
        self.plan.jkr_env
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

      # utility functions
      def send_mail(subject, addrs, body, files = [])
        attach_option = files.map{|file| "-a #{file}"}.join(" ")
        IO.popen("mutt #{addrs.join(' ')} -s #{subject.inspect} #{attach_option}", "w+") do |io|
          io.puts body
        end
      end

      def notify_im_kayac(username, message)
        Net::HTTP.post_form(URI.parse("http://im.kayac.com/api/post/#{username}"),
                            {'message'=>message})
      end

      def sh_(*args)
        puts "sh: #{args.join(' ')}"
        return system(*args)
      end

      def sh!(*args)
        puts "sh!: #{args.join(' ')}"
        unless system(*args)
          raise RuntimeError.new(args.join(" "))
        end
        true
      end

      # for backward compatibility
      alias :system_ :sh!

      # raise Error on failure by default
      alias :sh :sh!

      def su_sh(*args)
        puts "su_sh: #{args.join(' ')}"
        su_cmd = File.expand_path("../su_cmd", __FILE__)
        system_(su_cmd, args.join(' '))
      end

      def sudo_sh(*args)
        puts "sudo_sh: #{args.join(' ')}"
        system_((["sudo"] + args).join(' '))
      end

      def drop_caches()
        su_sh('echo 1 > /proc/sys/vm/drop_caches')
      end

      def checkout_git(dir, repo_url, branch)
        if ! File.directory?(dir)
          sh! "git clone #{repo_url} #{dir}"
        end

        Dir.chdir(dir) do
          if ! File.exists?(".git")
            sh! "git clone #{repo_url} ."
          end

          sh "git checkout -t origin/#{branch}"
          sh! "git pull"

          sh! "git rev-parse HEAD > #{@plan.resultset_dir + '/git-commit.log'}"
        end
      end
    end
  end
end
