
class Jkr
  class Analysis
    def self.analyze(env, resultset_num)
      resultset_num = sprintf "%05d", resultset_num.to_i
      resultset_dir = Dir.glob(File.join(env.jkr_result_dir, resultset_num)+"*")
      if resultset_dir.size != 1
        raise RuntimeError.new "cannot specify resultset dir (#{resultset_dir.join(" ")})"
      end
      resultset_dir = resultset_dir.first

      plan_files = Dir.glob(File.join(resultset_dir, "*.plan"))
      if plan_files.size == 0
        raise RuntimeError.new "cannot find plan file"
      elsif plan_files.size > 1
        raise RuntimeError.new "there are two or more plan files"
      end
      plan_file_path = plan_files.first

      plan = Jkr::Plan.new(env, nil,
                           :plan_path => plan_file_path,
                           :plan_search_path => File.dirname(plan_file_path))

      Jkr::AnalysisUtils.define_analysis_utils(resultset_dir, plan)
      plan.do_analysis()
      Jkr::AnalysisUtils.undef_analysis_utils(plan)
    end
  end
end
