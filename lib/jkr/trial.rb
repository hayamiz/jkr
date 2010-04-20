
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

      var_combs.map do |var_comb|
        result_dir = Utils.reserve_next_dir(resultset_dir)
        Trial.new(result_dir, plan, plan.params.merge(var_comb))
      end
    end

    def self.run(env, plan)
      plan_suffix = File.basename(plan.file_path, ".plan")
      resultset_dir = Utils.reserve_next_dir(env.jkr_result_dir, plan_suffix)
      trials = self.make_trials(resultset_dir, plan)

      FileUtils.copy_file(plan.file_path,
                          File.join(resultset_dir, File.basename(plan.file_path)))
      params = plan.params.merge(plan.vars)
      plan.prep.call(params)
      trials.each do |trial|
        trial.run
      end
      plan.cleanup.call(params)
    end

    def initialize(result_dir, plan, params)
      @result_dir = result_dir
      @plan = plan
      @params = params
    end
    private :initialize

    def run()
      def @params.method_missing(name, *args)
        self[name]
      end

      Jkr::TrialUtils.define_routine_utils(@result_dir, @plan, @params)
      @plan.routine.call(@params)
    end
  end
end
