
require 'fileutils'
require 'jkr/utils'

class Jkr
  class Trial
    attr_reader :params
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
        result_dir = Utils.reserve_next_dir(resultset_dir)
        Trial.new(result_dir, plan, params)
      end
    end

    def self.run(env, plan, delete_files_on_error = true)
      plan_suffix = File.basename(plan.file_path, ".plan")
      plan_suffix += "_#{plan.short_desc}" if plan.short_desc
      resultset_dir = Utils.reserve_next_dir(env.jkr_result_dir, plan_suffix)
      plan.resultset_dir = resultset_dir

      begin
        trials = self.make_trials(resultset_dir, plan)

        FileUtils.copy_file(plan.file_path,
                            File.join(resultset_dir, File.basename(plan.file_path)))
        params = plan.params.merge(plan.vars)
        plan.freeze
        plan.prep.call(plan)
        trials.each do |trial|
          trial.run
        end
        plan.cleanup.call(plan)
      rescue Exception => err
        if delete_files_on_error
          FileUtils.rm_rf(resultset_dir)
        end
        raise err
      end
    end

    def initialize(result_dir, plan, params)
      @result_dir = result_dir
      @plan = plan
      @params = params
    end
    private :initialize

    def run()
      Jkr::TrialUtils.define_routine_utils(@result_dir, @plan, @params)
      @plan.routine.call(@plan, @params)
      Jkr::TrialUtils.undef_routine_utils(@plan)
    end
  end
end
