
require 'fileutils'
require 'popen4'
require 'thread'

require 'jkr/userutils'

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
    # info about processes spawned by me
    def procdb
      @procdb ||= Hash.new
    end
    def procdb_spawn(pid, command)
      @procdb_mutex.synchronize do
        self.procdb[pid] = {:pid => pid, :command => command, :status => nil}
      end
    end
    def procdb_update_status(pid, status)
      @procdb_mutex.synchronize do
        if self.procdb[pid]
          self.procdb[pid][:status] = status
        end
      end
    end
    def procdb_get(pid)
      @procdb_mutex.synchronize do
        self.procdb[pid]
      end
    end
    def procdb_get_status(pid)
      proc = self.procdb_get(pid)
      proc && proc[:status]
    end
    def procdb_get_command(pid)
      proc = self.procdb_get(pid)
      proc && proc[:status]
    end

    def cmd(*args)
      @procdb_mutex ||= Mutex.new
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
      args.map!(&:to_s)
      command = args.join(" ")
      t = Thread.new {
        status = POpen4::popen4(command){|p_stdout, p_stderr, p_stdin, p_id|
          pid = p_id
          procdb_spawn(p_id, command)
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
        }
        procdb_spawn(pid, command)
        procdb_update_status(pid, status)
        raise ArgumentError.new("Invalid command: #{command}") unless status
        status
      }
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
        :kill_on_exit => false
      }.merge(options)
      options[:wait] = false

      args.push(options)
      pid = cmd(*args)

      err = nil
      begin
        yield
      rescue Exception => e
        err = e
      end
      
      if options[:kill_on_exit]
        Process.kill(:INT, pid)
      else
        if err
          Process.kill(:TERM, pid)
        else
          begin
            Process.waitpid(pid)
          rescue Errno::ECHILD
          end
          status = procdb_get_status(pid)
          unless status && status.exitstatus == 0
            command = procdb_get_command(pid) || "Unknown command"
            raise RuntimeError.new("'#{command}' failed.")
          end
        end
      end

      raise err if err
    end
  end

  class TrialUtils
    def self.undef_routine_utils(plan)
      plan.routine.binding.eval <<EOS
undef result_file
undef result_file_name
undef touch_result_file
undef with_result_file
EOS
    end

    def self.define_routine_utils(result_dir, plan, params)
      line = __LINE__; src = <<EOS
def result_file_name(basename)
  File.join(#{result_dir.inspect}, basename)
end

def result_file(basename, mode = "a+")
  path = result_file_name(basename)
  File.open(path, mode)
end

def touch_result_file(basename, options = {})
  path = result_file_name(basename)
  FileUtils.touch(path, options)
  path
end

def with_result_file(basename, mode = "a+")
  file = result_file(basename, mode)
  err = nil
  begin
    yield(file)
  rescue Exception => e
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

  class AnalysisUtils
    def self.undef_analysis_utils(plan)
      plan.analysis.binding.eval <<EOS
undef resultset
undef result_file
undef result_file_name
undef with_result_file
undef common_file
undef common_file_name
undef with_common_file
EOS
    end

    def self.define_analysis_utils(resultset_dir, plan)
      line = __LINE__; src = <<EOS
def resultset()
  dirs = Dir.glob(File.join(#{resultset_dir.inspect}, "*"))
  dirs.map{|dir| File.basename dir}.select{|basename|
    basename =~ /\\A\\d{3,}\\Z/
  }
end

def result_file_name(num, basename)
  if num.is_a? Integer
    num = sprintf "%03d", num
  end
  File.join(#{resultset_dir.inspect}, num, basename)
end

def result_file(num, basename, mode = "r")
  path = result_file_name(num, basename)
  File.open(path, mode)
end

def common_file_name(basename)
  File.join(#{resultset_dir.inspect}, basename)
end

def common_file(basename, mode = "r")
  path = common_file_name(basename)
  File.open(path, mode)
end

def with_common_file(basename, mode = "r")
  file = common_file(basename, mode)
  err = nil
  begin
    yield(file)
  rescue Exception => e
    err = e
  end
  file.close
  raise err if err
  file.path
end

def with_result_file(basename, mode = "r")
  file = result_file(basename, mode)
  err = nil
  begin
    yield(file)
  rescue Exception => e
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
