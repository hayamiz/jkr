require 'thor'
require 'term/ansicolor'

module Jkr
  class CLI < ::Thor
    include Term::ANSIColor

    class_option :debug, :type => :boolean
    class_option :directory, :type => :string, :default => Dir.pwd, :aliases => :C

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
      queue_dir  = File.join(dir, "jkr", "queue")

      puts "Preparing a new Jkr environment ... @ #{dir}"

      [jkr_dir, result_dir, plan_dir, script_dir, queue_dir].each do |dir|
        puts "  making directory: #{dir}"
        FileUtils.mkdir(dir)
      end

      [result_dir, plan_dir, script_dir, queue_dir].each do |dir|
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
      begin
        @jkr_env = Jkr::Env.new(options[:directory])
      rescue Errno::ENOENT
        puts(red("[ERROR] jkr dir not found at #{@options[:directory]}"))
        puts(red("        Maybe you are in a wrong directory."))
        exit(false)
      end

      plans = @jkr_env.plans.map do |plan_file_path|
        plan = Jkr::Plan.new(@jkr_env, nil, :plan_path => plan_file_path)
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
      @jkr_env = Jkr::Env.new(options[:directory])

      if options[:debug]
        delete_files_on_error = false
      else
        delete_files_on_error = true
      end

      if plan_names.size > 0
        plan_name = plan_names.first
        plan_file = find_plan_file(plan_name)

        unless plan_file
          raise ArgumentError.new("No such plan: #{plan_name}")
        end

        plan = Jkr::Plan.new(@jkr_env, nil, :plan_path => plan_file)
        Jkr::Trial.run(@jkr_env, plan, delete_files_on_error)
      end

      # run queued plans

      # show estimated execution time first
      queued_plans = Dir.glob(File.expand_path('*.plan', @jkr_env.jkr_queue_dir))

      if queued_plans.size > 0
        puts("")
        puts("== Execution time estimates ==")
        total_time = 0
        queued_plans.each do |plan_path|
          plan = Jkr::Plan.new(@jkr_env, nil, :plan_path => plan_path)
          if plan.exec_time_estimate
            time_sec = plan.exec_time_estimate.call(plan)
            time = pretty_time(time_sec)
          else
            total_time = nil
            time = "N/A"
          end

          if total_time
            total_time += time_sec
          end

          puts("  * #{File.basename(plan_path)}:\t#{time}")
        end
        puts("")
        if total_time
          puts("  * Total: #{pretty_time(total_time)}")
        else
          puts("  * Total: N/A")
        end
        puts("")
      end

      process_queue = true
      while process_queue
        Dir.mktmpdir do |tmpdir|
          plan_file = nil

          DirLock.lock(@jkr_env.jkr_queue_dir) do
            queued_plans = Dir.glob(File.expand_path('*.plan',
                                                     @jkr_env.jkr_queue_dir))
            if queued_plans.empty?
              process_queue = false
              break
            end

            queued_plan = queued_plans.sort.first
            plan_file = File.expand_path(File.basename(queued_plan).gsub(/\A\d{5}\./, ''), tmpdir)
            FileUtils.copy(queued_plan, plan_file)
            FileUtils.remove(queued_plan)
          end
          break unless process_queue

          plan = Jkr::Plan.new(@jkr_env, nil, :plan_path => plan_file)
          Jkr::Trial.run(@jkr_env, plan, delete_files_on_error)
        end
      end
    end

    desc "queue <plan>", "Push a plan into the execution queue"
    def queue(plan_name)
      @jkr_env = Jkr::Env.new(options[:directory])

      DirLock.lock(@jkr_env.jkr_queue_dir) do
        queue_ids = Dir.glob(File.expand_path('*.plan', @jkr_env.jkr_queue_dir)).map do |plan_file|
          if File.basename(plan_file) =~ /\A(\d{5})\./
            $~[1].to_i
          else
            nil
          end
        end.compact
        next_queue_id = ([-1] + queue_ids).max + 1

        plan_file = find_plan_file(plan_name)

        unless plan_file
         raise ArgumentError.new("No such plan: #{plan_name}")
        end

        FileUtils.copy(plan_file,
                       File.expand_path(sprintf("%05d.%s", next_queue_id,
                                                File.basename(plan_file)),
                                        @jkr_env.jkr_queue_dir))
      end
    end

    desc "analyze <result> [<result> ...]", "Run analysis script for executed results"
    def analyze(*result_ids)
      @jkr_env = Jkr::Env.new(options[:directory])

      result_ids.each do |arg|
        Jkr::Analysis.analyze(@jkr_env, arg)
      end
    end

    no_commands do
      def find_plan_file(plan_name)
        @jkr_env.plans.find do |plan_file_path|
          File.basename(plan_file_path) == plan_name + ".plan"
        end
      end
    end
  end

  class DirLock
    def self.lock(dir_path)
      File.open(File.expand_path('.lock', dir_path),
                File::RDWR | File::CREAT) do |f|
        f.flock(File::LOCK_EX)
        yield
      end
    end
  end
end
