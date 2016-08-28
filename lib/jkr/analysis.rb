
module Jkr
  class Analysis
    def self.analyze(env, resultset_num)
      resultset_num = sprintf "%05d", resultset_num.to_i
      resultset_dir = Dir.glob(File.join(env.jkr_result_dir, resultset_num)+"*")
      if resultset_dir.size != 1
        raise RuntimeError.new "cannot specify resultset dir (#{resultset_dir.join(" ")})"
      end
      resultset_dir = resultset_dir.first

      plan_files = Dir.glob(File.join(resultset_dir, "*.plan"))
      terminals = Hash.new
      plans = plan_files.map do |plan_file_path|
        plan_name = File.basename(plan_file_path, ".plan")
        plan = Jkr::Plan.new(env, plan_name,
                      :plan_path => plan_file_path,
                      :plan_search_path => File.dirname(plan_file_path))
        terminals[plan_name] = plan
      end

      plans.each do |plan|
        if plan.base_plan
          terminals.delete(plan.base_plan.plan_name)
        end
      end

      if terminals.size == 0
        raise RuntimeError.new "cannot find plan file"
      elsif terminals.size > 1
        raise RuntimeError.new "there are two or more plan files"
      end

      plan = terminals.first[1]
      plan.resultset_dir = File.dirname(plan.file_path)

      plan.do_analysis()
    end
  end
end
