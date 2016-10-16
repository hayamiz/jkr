
require 'fileutils'
require 'json'
require 'jkr/utils'

module Jkr
  class Trial
    attr_reader :params
    attr_reader :result_dir

    def self.make_trials(resultset_dir, plan)
      var_combs = [{}]
      plan.vars.each do |key, vals|
        var_combs = vals.map {|val|
          var_combs.map do |var_comb|
            var_comb.dup.merge(key => val)
          end
        }.flatten
      end

      params_list = var_combs.map{|var_comb| plan.params.merge(var_comb)}

      plan.param_filters.each do |filter|
        params_list = params_list.select(&filter)
      end

      params_list = params_list * plan.routine_nr_run

      params_list.map do |params|
        Trial.new(resultset_dir, plan, params)
      end
    end

    def self.pretty_time(seconds)
      hour = seconds / 3600
      min = (seconds - hour * 3600) / 60
      sec = seconds - hour * 3600 - min * 60

      sprintf("%02d:%02d:%02d", hour, min, sec)
    end

    def self.run(env, plan, delete_files_on_error = true)
      plan_suffix = File.basename(plan.file_path, ".plan")
      plan_suffix += "_#{plan.short_desc}" if plan.short_desc && plan.short_desc.size > 0
      resultset_dir = Utils.reserve_next_dir(env.jkr_result_dir, plan_suffix)
      plan.resultset_dir = resultset_dir
      FileUtils.mkdir_p(File.join(resultset_dir, "plan"))
      FileUtils.mkdir_p(File.join(resultset_dir, "script"))

      begin
        trials = self.make_trials(resultset_dir, plan)

        plan_dest_dir = File.join(resultset_dir, "plan")
        script_dest_dir = File.join(resultset_dir, "script")

        _plan = plan
        begin
          if _plan == plan # copy main plan file
            FileUtils.copy_file(_plan.file_path,
                                File.expand_path(File.basename(_plan.file_path), resultset_dir))
          else
            FileUtils.copy_file(_plan.file_path,
                                File.expand_path(File.basename(_plan.file_path),
                                               plan_dest_dir))
          end

          plan.used_scripts.each do |script_path|
            FileUtils.copy_file(script_path,
                                File.expand_path(File.basename(script_path),
                                                 script_dest_dir))
          end
        end while _plan = _plan.base_plan

        params = plan.params.merge(plan.vars)
        plan.freeze

        save_info(plan, :start_time => Time.now)

        # show estimated execution time if available
        if plan.exec_time_estimate
          puts("")
          puts("== estimated execution time: #{pretty_time(plan.exec_time_estimate.call(plan))} ==")
          puts("")
        end
      rescue Exception => err
        if delete_files_on_error
          FileUtils.rm_rf(resultset_dir)
        end
        raise err
      end

      resume(env, plan)
    end

    def self.resume(env, plan)
      trials = self.make_trials(plan.resultset_dir, plan)

      save_info(plan, :last_resume_time => Time.now)

      plan.do_prep()
      trials.each do |trial|
        begin
          trial.run
        rescue Exception => err
          failed_dir = File.expand_path("../_failed_" + File.basename(trial.result_dir),
                                        trial.result_dir)
          i = 1
          while Dir.exists?(failed_dir)
            failed_dir = File.expand_path("../_failed_" + File.basename(trial.result_dir) + "_#{i}",
                                          trial.result_dir)
            i += 1
          end
          FileUtils.mv(trial.result_dir, failed_dir)
          save_info(plan, :last_failure_time => Time.now)

          raise err
        end
      end
      plan.do_cleanup()

      save_info(plan, :finish_time => Time.now)
    end

    def self.save_info(plan, data = {})
      info_path = File.expand_path("INFO", plan.resultset_dir)
      unless File.exists?(info_path)
        File.open(info_path, "w") do |f|
          f.puts(JSON.pretty_generate({}))
        end
      end

      info_data = JSON.load(File.open(info_path))
      info_data = info_data.merge(data)

      File.open(info_path, "w") do |f|
        f.puts(JSON.pretty_generate(info_data))
      end
    end

    def initialize(resultset_dir, plan, params)
      @resultset_dir = resultset_dir
      @plan = plan
      @params = params
    end
    private :initialize

    def run()
      plan = @plan

      # check duplicate execution
      Dir.glob("#{@resultset_dir}/*").select do |path|
        File.basename(path) =~ /^[0-9]{5}$/
      end.each do |result_dir|
        params = Marshal.load(File.open("#{result_dir}/params.msh"))

        if params == @params
          # already executed trial. skip.
          return false
        end
      end

      # make result dir for this trial
      @result_dir = Utils.reserve_next_dir(@resultset_dir)

      Dir.chdir(@result_dir) do
        # save params
        File.open("#{@result_dir}/params.msh", "w") do |f|
          Marshal.dump(@params, f)
        end
        File.open("#{@result_dir}/params.json", "w") do |f|
          f.puts(JSON.pretty_generate(@params))
        end

        # reset plan.metastore
        plan.metastore.clear

        # define utility functions for plan.routine object
        Jkr::TrialUtils.define_routine_utils(@result_dir, @plan, @params)

        @plan.metastore[:vars] = @plan.vars.keys
        @plan.metastore[:trial_start_time] = Time.now
        @plan.do_routine(@plan, @params)
        @plan.metastore[:trial_end_time] = Time.now

        Jkr::TrialUtils.undef_routine_utils(@plan)

        # save plan.metastore
        Marshal.dump(@plan.metastore,
                     File.open("#{@result_dir}/metastore.msh", "w"))
        File.open("#{@result_dir}/metastore.json", "w") do |f|
          f.puts(JSON.pretty_generate(@plan.metastore))
        end
      end
    end
  end
end
