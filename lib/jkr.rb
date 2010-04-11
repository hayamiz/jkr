
class Jkr
  VERSION = '0.0.1'

  class ExperimentPlan
    attr_reader :params
    attr_reader :title
    attr_reader :desc
    attr_reader :options
    attr_reader :proc

    def initialize(title, desc, params, var_names, proc, options = {})
      @title = title
      @desc = desc
      @params = params
      @options = options
      @proc = proc
    end
  end

  class Executor
    def initialize
      @hooks = {}
    end

    def run(plan)
      plan.proc.call(plan.params)
    end
  end

  class Planner
    def initialize()
      @title = "no title"
      @desc = "no description"

      @vars = []
      @params = {}
      @options = {}

      @delayed_param_queue = []
    end

    def self.load(plan_file_path)
      plan = self.new
      plan_src = File.open(plan_file_path, "r").read
      plan.instance_eval(plan_src)
      
      plan
    end
    
    ## Functions for describing plans in '.plan' files below
    def title(plan_title)
      @title = plan_title.to_s
    end
    
    def description(plan_desc)
      @desc = plan_desc.to_s
    end
    
    def def_experiment_plan
      yield(self)

      params_set = [@params]
      var_names = []
      @vars.each do |var|
        var_name = var[0]
        var_vals = var[1]
        var_names.push(var_name)
        params_set = params_set.map{|params|
          var_vals.map do |var_val|
            params = params.dup
            params[var_name] = var_val
            params
          end
        }.flatten
      end

      params_set.map do |params|
        ExperimentPlan.new(@title, @desc, params, var_names)
      end
    end

    def param(arg)
      if arg.is_a? Hash
        # set param
        @params.merge!(arg)
      elsif arg.is_a? Symbol
        @params[arg]
      else
        raise ArgumentError.new("Jkr::Planner#param takes Hash or Symbol only.")
      end
    end

    def variable(arg)
      if arg.is_a? Hash
        arg.each do |key, val|
          @vars.push([key, val])
        end
      else
        raise ArgumentError.new("Jkr::Planner#param takes Hash or Symbol only.")
      end
    end

    def set_option(arg)
      @options.merge!(arg)
    end

    def discard_on_finish()
      self.set_option :discard_on_finish => true
    end
  end
end
