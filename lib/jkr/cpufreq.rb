#!/usr/bin/env ruby

require 'jkr/array'

class Jkr
  class Cpufreq
    def self.cpupath(cpu_idx = nil)
      if cpu_idx
        self.cpupath() + "/cpu#{cpu_idx}"
      else
        "/sys/devices/system/cpu"
      end
    end

    def self.cpufreqpath(cpu_idx = 0)
      cpupath(cpu_idx) + "/cpufreq"
    end

    def self.num_cpu()
      Dir.glob(cpupath("*")).select{|file| file =~ /cpu\d+$/}.size
    end
    
    def self.available?()
      (0..(self.num_cpu() - 1)).to_a.every?{|cpu_idx|
        File.exists?(cpufreqpath(cpu_idx))
      }
    end

    def self.config()
      Config.get()
    end

    def self.available_frequency(cpu_idx = 0)
      if self.available?
        File.read(cpufreqpath(cpu_idx) + "/scaling_available_frequencies").strip.split.map(&:to_i)
      else
        []
      end
    end

    class Config
      attr_reader :cpuconfigs

      def initialize(*args)
        @cpuconfigs = \
        if args.size == 0
          self.current_config
        elsif args.size == 1 && args.first.is_a?(Hash)
          arg = args.first
          if ! arg[:governor]
            raise ArgumentError.new("governor must be specified.")
          elsif arg[:governor] == "userspace" && ! arg[:frequency]
            raise ArgumentError.new("parameter :frequency is required for userspece governor")
          end

          Array.new(Cpufreq.num_cpu()){|idx|
            CpuConfig.new(idx, arg[:governor], arg)
          }
        elsif args.size == 1 && args.first.is_a?(Array) && args.first.every?{|arg| arg.is_a? CpuConfig}
          args.first
        elsif args.size == Cpufreq.num_cpu() && args.every?{|arg| arg.is_a? CpuConfig}
          args
        end
      end

      def self.get()
        cpuconfigs = Array.new(Cpufreq.num_cpu){|cpu_idx|
          CpuConfig.read_config(cpu_idx)
        }
        self.new(cpuconfigs)
      end

      def self.set(config)
        config.cpuconfigs.each_with_index{|cpuconfig, idx|
          CpuConfig.write_config(idx, cpuconfig)
        }
      end

      class CpuConfig
        attr_accessor :governor
        attr_accessor :params

        # cpu_idx is just a hint for gathering information
        def initialize(cpu_idx, gov, params = Hash.new)
          @governor = gov
          @freq = nil
          @params = params

          @cpu_idx = cpu_idx
          @available_freqs = Cpufreq.available_frequency(cpu_idx)

          case @governor
          when /\Aperformance\Z/
            # do nothing
          when /\Apowersave\Z/
            # do nothing
          when /\Auserspace\Z/
            if ! @freq = params[:frequency]
              raise ArgumentError.new("parameter :frequency is required for userspece governor")
            elsif ! @available_freqs.include?(params[:frequency])
              raise ArgumentError.new("Frequency not available: #{params[:frequency]}")
            end
          when /\Aondemand\Z/
            # TODO
          end
        end

        def frequency
          case @governor
          when /\Aperformance\Z/
            @available_freqs.max
          when /\Apowersave\Z/
            @available_freqs.min
          when /\Auserspace\Z/
            @freq
          when /\Aondemand\Z/
            File.read(Cpufreq.cpufreqpath(@cpu_idx) + "/scaling_cur_freq").strip.to_i
          end
        end

        def frequency=(freq)
          if @available_freqs.include?(freq)
            @freq = freq
          else
            raise ArgumentError.new("Frequency not available: #{freq}")
          end
        end

        def self.read_config(cpu_idx)
          gov = File.read(Cpufreq.cpufreqpath(cpu_idx) + "/scaling_governor").strip
          freq = nil

          case gov
          when /\Aperformance\Z/
            # do nothing
          when /\Aperformance\Z/
            # do nothing
          when /\Auserspace\Z/
            freq = File.read(Cpufreq.cpufreqpath(cpu_idx) + "/scaling_cur_freq").strip.to_i
          when /\Aondemand\Z/
            # TODO: read parameters
          end

          CpuConfig.new(cpu_idx, gov, {:frequency => freq})
        end

        def self.write_config(cpu_idx, cpuconfig)
          File.open(Cpufreq.cpufreqpath(cpu_idx) + "/scaling_governor", "w"){|file|
            file.puts cpuconfig.governor
          }
          case cpuconfig.governor
          when /\Aperformance\Z/
            # do nothing
          when /\Aperformance\Z/
            # do nothing
          when /\Auserspace\Z/
            File.open(Cpufreq.cpufreqpath(cpu_idx) + "/scaling_setspeed", "w"){|file|
              file.puts cpuconfig.frequency
            }
          when /\Aondemand\Z/
            # TODO: parameters
          end
        end
      end
    end
  end
end
