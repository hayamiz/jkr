
class Jkr
  class CpuUsageMonitor
    def initialize
      @checkpoints = []

      self.checkpoint
    end

    def read_stat
      stat_str = `cat /proc/stat`
      cpu_total = nil
      cpus = Array.new
      stat_str.each_line do |line|
        case line
        when /cpu (.*)$/
          user, nice, sys, idle, *rest = $~[1].strip.split.map(&:to_i)
          rest = rest.inject(&:+)
          cpu_total = {:user => user, :sys => sys, :nice => nice, :idle => idle, :rest => rest}
        when /cpu(\d+) (.*)$/
          idx = $~[1].to_i
          user, nice, sys, idle, *rest = $~[2].strip.split.map(&:to_i)
          cpus[idx] = {:user => user, :sys => sys, :nice => nice, :idle => idle, :rest => rest}
        end
      end

      {:system => cpu_total,
        :cpus => cpus}
    end

    def checkpoint
      @checkpoints.push(self.read_stat)
    end

    def reset
      @checkpoints = []
    end

    def checkpoint_and_get_usage
      self.checkpoint
      self.get_last_usage
    end

    def get_usage
      if @checkpoints.size < 1
        raise RuntimeError.new("Checkpointing is required")
      end

      self.calc_usage(self.read_stat[:system], @checkpoints.last[:system])
    end

    def get_last_usage
      if @checkpoints.size < 2
        raise RuntimeError.new("At least two checkpoints are required")
      end

      self.calc_usage(@checkpoints[@checkpoints.size - 2][:system], @checkpoints[@checkpoints.size - 1][:system])
    end

    def calc_usage(stat1, stat2)
      stat1_clk, stat2_clk = [stat1, stat2].map{|stat|
        stat.values.inject(&:+)
      }
      if stat1_clk > stat2_clk
        stat1, stat2, stat1_clk, stat2_clk = [stat2, stat1, stat2_clk, stat1_clk]
      elsif stat1_clk == stat2_clk
        raise RuntimeError.new("Same clock count. cannot calc usage.")
      end
      clk_diff = (stat2_clk - stat1_clk).to_f
      ret = Hash.new
      [:user, :sys, :nice, :idle].map{|key|
        ret[key] = (stat2[key] - stat1[key]) / clk_diff
      }

      ret
    end
  end
end
