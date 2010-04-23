
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

      result = []
      bufstr = ""
      while ! file.eof?
        bufstr += file.read(BLOCKSIZE)
        blocks = bufstr.split(separator)
        bufstr = blocks.pop
        blocks.each do |block|
          ret = proc.call(block)
          result.push(ret) if ret
        end
      end
      ret = proc.call(bufstr)
      result.push(ret) if ret

      result
    end

    def self.read_rowseq(io_or_filepath, &block)
      self.read_blockseq(io_or_filepath, "\n", &block)
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

    def self.read_mpstat(io_or_filepath)
      hostname = `hostname`.strip
      
      date = nil
      last_time = nil
      self.read_blockseq(io_or_filepath) do |blockstr|
        if blockstr =~ /^Linux/ && blockstr =~ /(\d{2})\/(\d{2})\/(\d{2})$/
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
          result[:labels] = header
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
  end
end
