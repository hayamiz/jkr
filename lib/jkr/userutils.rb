
require 'kconv'
require 'time'
require 'date'
require 'csv'

class Jkr
  class SysUtils
    def self.cpu_cores()
      self.num_cores()
    end

    def self.num_cores()
      `grep "core id" /proc/cpuinfo|wc -l`.to_i
    end

    def self.num_processors()
      `grep "physical id" /proc/cpuinfo|sort|uniq|wc -l`.to_i
    end
  end

  class DataUtils
    BLOCKSIZE = 268435456 # 256MB
    def self.read_blockseq(io_or_filepath, separator = "\n\n", &proc)
      file = io_or_filepath
      if ! io_or_filepath.is_a? IO
        file = File.open(io_or_filepath, "r")
      end
      proc ||= lambda do |blockstr|
        unless blockstr.strip.empty?
          blockstr.split
        else
          nil
        end
      end

      #result = []
      #bufstr = ""
      #while ! file.eof?
      #  bufstr += file.read(BLOCKSIZE)
      #  blocks = bufstr.split(separator)
      #  bufstr = blocks.pop
      #  blocks.each do |block|
      #    ret = proc.call(block)
      #    result.push(ret) if ret
      #  end
      #end
      #ret = proc.call(bufstr)
      #result.push(ret) if ret
      result = file.read.split(separator).map do |x|
        proc.call(x)
      end.compact

      result
    end

    def self.read_rowseq(io_or_filepath, &block)
      self.read_blockseq(io_or_filepath, "\n", &block)
    end

    def self.read_sar(sar_filepath)
      labels = nil
      date = nil
      last_time = nil
      idx = 0
      self.read_rowseq(sar_filepath){|rowstr|
        if rowstr =~ /^Linux/ && rowstr =~ /(\d{2})\/(\d{2})\/(\d{2})/
          y = $~[3].to_i; m = $~[1].to_i; d = $~[2].to_i
          date = Date.new(2000 + y, m, d)
          next
        else
          row = Hash.new

          time, *vals = rowstr.split

          if vals.size == 0
            next
          end
          if vals.every?{|val| val =~ /\A\d+(?:\.\d+)?\Z/ }
            vals = vals.map(&:to_f)
          else
            # label line
            labels = vals
            next
          end

          unless date
            raise StandardError.new("cannot find date information in sar log")
          end
          unless labels
            raise StandardError.new("no label information")
          end

          unless time =~ /(\d{2}):(\d{2}):(\d{2})/
            if time =~ /Average/
              next
            end
            raise StandardError.new("Invalid time format: #{time}")
          else
            time = Time.local(date.year, date.month, date.day,
                              $~[1].to_i, $~[2].to_i, $~[3].to_i)
            if last_time && time < last_time
              date += 1
              time = Time.local(date.year, date.month, date.day,
                                $~[1].to_i, $~[2].to_i, $~[3].to_i)
            end

            row[:time] = time
            row[:data] = Hash.new
            labels.each_with_index do |label,idx|
              row[:data][label] = vals[idx]
            end
            row[:labels] = labels

            last_time = time
          end
        end
        row
      }
    end

    def self.read_mpstat_avg(io_or_filepath)
      self.read_blockseq(io_or_filepath){|blockstr|
        if blockstr =~ /^Average:/
          result = Hash.new
          rows = blockstr.lines.map(&:strip)
          header = rows.shift.split
          header.shift
          result[:labels] = header
          result[:data] = rows.map { |row|
            vals = row.split
            vals.shift
            if vals.size != result[:labels].size
              raise RuntimeError.new("Invalid mpstat data")
            end
            vals.map{|val|
              begin
                Float(val)
              rescue ArgumentError
                val
              end
            }
          }
          result
        end
      }.last
    end

    # Format of returned value
    # [{
    #    :time => <Time>,
    #    :labels => [:cpu, :usr, :nice, :sys, :iowait, :irq, ...],
    #    :data => [{:cpu => "all", :usr => 0.11, :nice => 0.00, ...],
    #              {:cpu => 0, :usr => 0.12, :nice => 0.00, ...},
    #               ...]
    #  },
    #  ...]
    #
    def self.read_mpstat(io_or_filepath)
      hostname = `hostname`.strip
      
      date = nil
      last_time = nil
      self.read_blockseq(io_or_filepath) do |blockstr|
        if blockstr =~ /Linux/ && blockstr =~ /(\d{2})\/(\d{2})\/(\d{2})/
          # the first line
          y = $~[3].to_i; m = $~[1].to_i; d = $~[2].to_i
          date = Date.new(2000 + y, m, d)
          next
        else
          # it's a data block, maybe
          unless date
            $stderr.puts "Cannot find date in your mpstat log. It was assumed today."
            date = Date.today
          end

          result = Hash.new
          rows = blockstr.lines.map(&:strip)
          header = rows.shift.split
          next if header.shift =~ /Average/
          result[:labels] = header.map do |label|
            {
              "CPU" => :cpu, "%usr" => :usr, "%user" => :user,
              "%nice" => :nice, "%sys" => :sys, "%iowait" => :iowait,
              "%irq" => :irq, "%soft" => :soft, "%steal" => :steal,
              "%guest" => :guest, "%idle" => :idle
            }[label] || label
          end
          time = nil
          result[:data] = rows.map { |row|
            vals = row.split
            wallclock = vals.shift
            unless time
              unless wallclock =~ /(\d{2}):(\d{2}):(\d{2})/
                raise RuntimeError.new("Cannot extract wallclock time from mpstat data")
              end
              time = Time.local(date.year, date.month, date.day,
                                $~[1].to_i, $~[2].to_i, $~[3].to_i)
              if last_time && time < last_time
                date += 1
                time = Time.local(date.year, date.month, date.day,
                                  $~[1].to_i, $~[2].to_i, $~[3].to_i)
              end
              result[:time] = time
              last_time = time
            end
            if vals.size != result[:labels].size
              raise RuntimeError.new("Invalid mpstat data")
            end

            record = Hash.new
            vals.each_with_index{|val, idx|
              label = result[:labels][idx]
              val = if val =~ /\A\d+\Z/
                      val.to_i
                    else
                      begin
                        Float(val)
                      rescue ArgumentError
                        val
                      end
                    end
              record[label] = val
            }

            record
          }
          result
        end
      end
    end

    #
    # This function parses _io_or_filepath_ as an iostat log and
    # returns the parsed result.
    #
    # _block_ :: If given, invoked for each iostat record like
    #            block.call(t, record)
    #            t ... wallclock time of the record
    #            record ... e.g. {"sda" => {"rrqm/s" => 0.0, ...}, ...}
    #
    def self.read_iostat(io_or_filepath, &block)
      hostname = `hostname`.strip
      
      date = nil
      last_time = nil
      sysname_regex = Regexp.new(Regexp.quote("#{`uname -s`.strip}"))
      self.read_blockseq(io_or_filepath) do |blockstr|
        if blockstr =~ sysname_regex
          # the first line
          if blockstr =~ /(\d{2})\/(\d{2})\/(\d{2})$/
            y = $~[3].to_i; m = $~[1].to_i; d = $~[2].to_i
            date = Date.new(2000 + y, m, d)
            next
          end
        else
          rows = blockstr.lines.map(&:strip)
          timestamp = rows.shift
          time = nil
          if timestamp =~ /(\d{2})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2}):(\d{2})/
            y = $~[3].to_i; m = $~[1].to_i; d = $~[2].to_i
            time = Time.local(y, m, d, $~[4].to_i, $~[5].to_i, $~[6].to_i)
          elsif date && timestamp =~ /Time: (\d{2}):(\d{2}):(\d{2})/
            time = Time.local(date.year, date.month, date.day,
                              $~[1].to_i, $~[2].to_i, $~[3].to_i)
          end
          
          unless time
            unless date
              raise StandardError.new("Cannot find date in your iostat log: #{io_or_filepath}")
            end
            raise StandardError.new("Cannot find timestamp in your iostat log: #{io_or_filepath}")
          end

          labels = rows.shift.split
          unless labels.shift =~ /Device:/
            raise StandardError.new("Invalid iostat log: #{io_or_filepath}")
          end

          record = Hash.new
          rows.each do |row|
            vals = row.split
            dev = vals.shift
            unless vals.size == labels.size
              raise StandardError.new("Invalid iostat log: #{io_or_filepath}")
            end
            record_item = Hash.new
            labels.each do |label|
              record_item[label] = vals.shift.to_f
            end
            record[dev] = record_item
          end

          if block.is_a? Proc
            block.call(time, record)
          end

          [time, record]
        end
      end
    end

    def self.read_csv(io_or_filepath, fs = ",", rs = nil, &proc)
      if io_or_filepath.is_a?(String) && File.exists?(io_or_filepath)
        io_or_filepath = File.open(io_or_filepath, "r")
      end

      result = []
      proc ||= lambda{|row| row}
      CSV.parse(io_or_filepath).each do |row|
        ret = proc.call(row)
        result.push ret if ret
      end
      result
    end

    class << self
      def read_top(io_or_filepath, opt = {}, &proc)
        opt[:start_time] ||= Time.now

        def parse_block(block, opt)
          y = opt[:start_time].year
          m = opt[:start_time].month
          d = opt[:start_time].day

          lines = block.lines.map(&:strip)
          head_line = lines.shift

          unless head_line =~ /(\d{2}):(\d{2}):(\d{2})/
            raise ArgumentError.new("Invalid top(3) data")
          end
          time = Time.local(y, m, d, $~[1].to_i, $~[2].to_i, $~[3].to_i)

          while ! (lines[0] =~ /\APID/)
            line = lines.shift
          end
          labels = lines.shift.split.map do |key|
            {"PID" => :pid, "USER" => :user, "PR" => :pr, "NI" => :ni,
              "VIRT" => :virt, "RES" => :res, "SHR" => :shr, "S" => :s,
              "%CPU" => :cpu, "%MEM" => :mem, "TIME+" => :time_plus,
              "COMMAND" => :command}[key] || key
          end

          lines = lines.select{|line| ! line.empty?}
          if opt[:top_k]
            lines = lines.first(opt[:top_k])
          end
          lines.map do |line|
            record = Hash.new
            record[:time] = time
            line.split.each_with_index do |val, idx|
              key = labels[idx]
              if val =~ /\A(\d+)([mg]?)\Z/
                record[key] = Integer($~[1])
                if ! $~[2].empty?
                  record[key] *= {'g' => 2**20, 'm' => 2**10}[$~[2]]
                end
              elsif val =~ /\A(\d+\.\d+)([mg]?)\Z/
                record[key] = Float($~[1])
                if ! $~[2].empty?
                  record[key] *= {'g' => 2**20, 'm' => 2**10}[$~[2]]
                end
              elsif val =~ /\A(\d+):(\d+\.\d+)\Z/
                record[key] = Integer($~[1])*60 + Float($~[2])
              else
                record[key] = val
              end
            end

            record
          end
        end

        File.open(io_or_filepath, "r").read.split("\n\n\n").map do |block|
          parse_block(block, opt)
        end
      end
    end
  end
end
