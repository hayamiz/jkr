
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

      def @params.method_missing(name, *args)
        self[name.to_sym]
      end
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
      @execution = nil

      @delayed_param_queue = []
    end

    def self.load_plan(plan_file_path)
      planner = self.new
      plan_src = File.open(plan_file_path, "r").read
      planner.instance_eval(plan_src, plan_file_path, 0)
      # load(plan_file_path)
          
      planner.generate_plans
    end
    
    def generate_plans
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
        ExperimentPlan.new(@title, @desc, params, var_names, @execution, @options)
      end
    end

    ## Functions for describing plans in '.plan' files below
    def title(plan_title)
      @title = plan_title.to_s
    end
    
    def description(plan_desc)
      @desc = plan_desc.to_s
    end
    
    def def_experiment_plan(&proc)
      proc.call(self)
    end

    def def_execution(&proc)
      @execution = proc
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
