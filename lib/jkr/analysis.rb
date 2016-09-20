
module Jkr
  class Analysis
    def self.analyze(env, resultset_num)
      resultset_num = sprintf "%05d", resultset_num.to_i
      resultset_dir = Dir.glob(File.join(env.jkr_result_dir, resultset_num)+"*")
      if resultset_dir.size != 1
        raise RuntimeError.new "cannot specify resultset dir (#{resultset_dir.join(" ")})"
      end
      resultset_dir = resultset_dir.first

      plan = Plan.create_by_result_id(env, resultset_num)
      plan.resultset_dir = File.dirname(plan.file_path)

      plan.do_analysis()
    end
  end
end
