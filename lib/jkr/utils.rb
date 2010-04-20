
require 'fileutils'
require 'popen4'
require 'time'
require 'date'

class Jkr
  class Utils
    def self.reserve_next_dir(dir, suffix = "")
      dirs = Dir.glob("#{dir}#{File::SEPARATOR}???*")
      max_num = -1
      dirs.each do |dir|
        if /\A[0-9]+/ =~ File.basename(dir)
          max_num = [$~[0].to_i, max_num].max
        end
      end
      
      num = max_num + 1
      dir = "#{dir}#{File::SEPARATOR}" + sprintf("%03d%s", num, suffix)
      FileUtils.mkdir(dir)
      dir
    end
  end

  module PlanUtils
    def cmd(*args)
      options = (if args.last.is_a? Hash
                   args.pop
                 else
                   {}
                 end)
      options = {
        :wait   => true,
        :timeout => 0,
        :raise_failure => true,
        :stdin  => nil,
        :stdout => [$stdout],
        :stderr => [$stderr]
      }.merge(options)

      if options[:timeout] > 0 && ! options[:wait]
        raise ArgumentError.new("cmd: 'wait' must be true if 'timeout' specified.")
      end

      start_time = Time.now
      pid = nil
      status = nil
      args.flatten!
      command = args.join(" ")
      t = Thread.new do
        status = POpen4::popen4(command) do |p_stdout, p_stderr, p_stdin, p_id|
          pid = p_id
          stdouts = if options[:stdout].is_a? Array
                      options[:stdout]
                    else
                      [options[:stdout]]
                    end
          stderrs = if options[:stderr].is_a? Array
                      options[:stderr]
                    else
                      [options[:stderr]]
                    end
          
          read_fds = [p_stdout, p_stderr]
          if options[:stdin]
            read_fds << options[:stdin]
          else
            p_stdin.close
          end
          
          begin
            begin
              ready = IO.select(read_fds)
            rescue IOError => err
              if options[:stdin] && options[:stdin].closed?
                read_fds.reject!{|fd| fd == options[:stdin]}
                p_stdin.close
              end
            end
            
            ready[0].each do |io|
              begin
                buf = io.read_nonblock(4096)
              rescue EOFError => err
                read_fds.reject!{|fd| fd == io}
              end
              
              if io == p_stdout
                stdouts.each do |out|
                  out.print buf
                end
              elsif io == p_stderr
                stderrs.each do |out|
                  out.print buf
                end
              else
                p_stdin.print(buf)
              end
            end
          end while ! read_fds.empty?
        end
      end
      timekeeper = nil
      if options[:timeout] > 0
        timekeeper = Thread.new do
          sleep(options[:timeout])
          begin
            Process.kill(:INT, pid)
          rescue Errno::ESRCH # No such process
          end
        end
      end
      if options[:wait]
        t.join
        if options[:raise_failure] && status.exitstatus != 0
          raise RuntimeError.new("'#{command}' failed.")
        end
      end
      while ! pid
        sleep 0.001 # do nothing
      end

      pid
    end

    def with_process(*args)
      options = (if args.last.is_a? Hash
                   args.pop
                 else
                   {}
                 end )
      options = {
        :kill_on_exit => false,
        :wait => false
      }.merge(options)

      args.push(options)
      pid = cmd(*args)

      err = nil
      begin
        yield
      rescue StandardError => e
        err = e
      end
      
      if options[:kill_on_exit]
        Process.kill(:INT, pid)
      else
        begin
          Process.waitpid(pid)
        rescue Errno::ECHILD
        end
      end
    end
  end

  class SysUtils
    def self.cpu_cores()
      `grep "core id" /proc/cpuinfo|wc -l`.to_i
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
            data = Hash.new
            result[:labels].zip(vals).each{|pair|
              val = begin
                      Float(pair[1])
                    rescue ArgumentError
                      pair[1]
                    end
              data[pair[0]] = val
            }
            data
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
        if blockstr.include?(hostname) && blockstr =~ /(\d{2})\/(\d{2})\/(\d{2})/
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
              unless wallclock =~ /\d{2}:\d{2}:\d{2}/
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
            data = Hash.new
            result[:labels].zip(vals).each{|pair|
              val = begin
                      Float(pair[1])
                    rescue ArgumentError
                      pair[1]
                    end
              data[pair[0]] = val
            }
            data
          }
        end
      end
    end
  end

  class TrialUtils
    def self.define_routine_utils(result_dir, plan, params)
      line = __LINE__; src = <<EOS
def result_file(basename, mode = "a+")
  path = File.join(#{result_dir.inspect}, basename)
  File.open(path, mode)
end

def touch_result_file(basename, options = {})
  path = File.join(#{result_dir.inspect}, basename)
  FileUtils.touch(path, options)
  path
end

def with_result_file(basename, mode = "a+")
  file = result_file(basename, mode)
  err = nil
  begin
    yield(file)
  rescue StandardError => e
    err = e
  end
  file.close
  raise err if err
  file.path
end
EOS
      plan.routine.binding.eval(src, __FILE__, line)
    end
  end
end
