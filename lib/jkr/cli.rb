require 'thor'
require 'term/ansicolor'

module Jkr
  class CLI < ::Thor
    include Term::ANSIColor

    class_option :debug, :type => :boolean
    class_option :directory, :type => :string, :default => nil, :aliases => :C

    def self.exit_on_failure?
      true
    end

    desc "init", "Initialize a Jkr environment"
    def init()
      dir = options[:directory]

      jkr_dir    = File.join(dir, "jkr")
      result_dir = File.join(dir, "jkr", "result")
      plan_dir   = File.join(dir, "jkr", "plan")
      script_dir = File.join(dir, "jkr", "script")

      puts "Preparing a new Jkr environment ... @ #{dir}"

      [jkr_dir, result_dir, plan_dir, script_dir].each do |dir|
        puts "  making directory: #{dir}"
        FileUtils.mkdir(dir)
      end

      [result_dir, plan_dir, script_dir].each do |dir|
        File.open(File.expand_path(".gitdir", dir), "w") do |_|
        end
      end

      puts "  preparing an example plan: example.plan"
      FileUtils.cp(File.expand_path("../../etc/example.plan", __dir__),
                   File.join(plan_dir, "example.plan"))

      puts ""
      puts "... done"
    end

    desc "list", "List executable plans"
    def list()
      @jkr_env = create_env()

      plans = Dir.glob("#{@jkr_env.jkr_plan_dir}/*.plan").map do |plan_file_path|
        plan = Jkr::Plan.create_by_name(@jkr_env, File.basename(plan_file_path, ".plan"))
        [File.basename(plan_file_path, ".plan"), plan.title]
      end

      if ENV["JKR_ZSHCOMP_HELPER"]
        plans.each do |plan_name, plan_title|
          puts "#{plan_name}[#{plan_title}]"
        end
        return
      end

      puts "Existing plans:"
      puts
      maxlen = plans.map{|plan| plan[0].size}.max
      plans.each do |plan|
        printf(" %#{maxlen}s : %s\n", plan[0], plan[1])
      end
      puts
    end

    desc "execute <plan> [<plan> ...]", "Execute plans"
    def execute(*plan_names)
      @jkr_env = create_env()

      if options[:debug]
        delete_files_on_error = false
      else
        delete_files_on_error = true
      end

      if plan_names.size > 0
        plan_name = plan_names.first
        plan = Jkr::Plan.create_by_name(@jkr_env, plan_name)
        Jkr::Trial.run(@jkr_env, plan, delete_files_on_error)
      end
    end

    desc "resume [<result> ...]", "Resume in-progress execution"
    def resume(*result_ids)
      @jkr_env = create_env()
      cur_result_id = Jkr::Env.find_result(Dir.pwd)
      if cur_result_id
        result_ids.push(cur_result_id)
      end

      result_ids.each do |rid|
        plan = Plan.create_by_result_id(@jkr_env, rid)
        Jkr::Trial.resume(@jkr_env, plan)
      end
    end

    desc "analyze [<result> ...]", "Run analysis script for executed results"
    def analyze(*result_ids)
      @jkr_env = create_env()

      # check if current dir is a result dir
      cur_result_id = Jkr::Env.find_result(Dir.pwd)
      if cur_result_id
        result_ids.push(cur_result_id)
      end

      result_ids.each do |arg|
        Jkr::Analysis.analyze(@jkr_env, arg)
      end
    end

    desc "query <result>", "Query interesting result"
    def query(result_id = nil)
      @jkr_env = create_env()

      if result_id == nil
        # check if current dir is a result dir
        cur_result_id = Jkr::Env.find_result(Dir.pwd)
        if cur_result_id
          result_id = cur_result_id
        else
          raise ArgumentError.new("Result ID must be specified.")
        end
      end

      result_dir = Dir.glob(sprintf("#{@jkr_env.jkr_result_dir}/%05d*", result_id.to_i)).first

      Dir.glob("#{result_dir}/[0-9][0-9][0-9][0-9][0-9]/metastore.msh").sort.each do |m|
        metastore = Marshal.load(File.open(m))
        params = Marshal.load(File.open(File.expand_path("../params.msh", m)))

        disp = metastore[:vars].map do |var|
          "#{var}: #{params[var].inspect}"
        end.join(", ")

        puts "#{File.basename(File.dirname(m))}	| #{disp}"
      end
    end

    no_commands do
      def find_plan_file(plan_name)
        @jkr_env.plans.find do |plan_file_path|
          File.basename(plan_file_path) == plan_name + ".plan"
        end
      end

      def create_env()
        begin
          if options[:directory]
            return Jkr::Env.new(options[:directory])
          else
            return Jkr::Env.new(Jkr::Env.find(Dir.pwd))
          end
        rescue Errno::ENOENT
          $stderr.puts(red("[ERROR] jkr dir not found at #{@options[:directory]}"))
          $stderr.puts(red("        Maybe you are in a wrong directory."))
          exit(false)
        end

      end
    end
  end

end # Jkr
