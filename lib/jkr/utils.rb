
require 'fileutils'
require 'popen4'
require 'thread'

require 'jkr/userutils'

class Barrier
  def initialize(num)
    @mux = Mutex.new
    @cond = ConditionVariable.new

    @num = num
    @cur_num = num
  end

  def wait()
    @mux.lock
    @cur_num -= 1
    if @cur_num == 0
      @cur_num = @num
      @cond.broadcast
    else
      @cond.wait(@mux)
    end
    @mux.unlock
  end
end

def system_(*args)
  puts "system_: #{args.join(' ')}"
  unless system(*args)
    raise RuntimeError.new(args.join(" "))
  end
end

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
      dir = "#{dir}#{File::SEPARATOR}" + sprintf("%05d%s", num, suffix)
      FileUtils.mkdir(dir)
      dir
    end
  end

  module PlanUtils
    # info about processes spawned by me
    def procdb
      @procdb ||= Hash.new
    end
    def procdb_spawn(pid, command, owner_thread)
      @procdb_mutex.synchronize do
        self.procdb[pid] = {
          :pid => pid,
          :command => command,
          :thread => owner_thread,
          :status => nil
        }
      end
    end
    def procdb_waitpid(pid)
      t = nil
      @procdb_mutex.synchronize do
        if self.procdb[pid]
          t = self.procdb[pid][:thread]
        end
      end
      t.join if t
    end
    def procdb_resetpid(pid)
      @procdb_mutex.synchronize do
        if self.procdb[pid]
          self.procdb.delete(pid)
        end
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
      proc && proc[:command]
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
      barrier = Barrier.new(2)
      process_exited = false

      t = Thread.new {
        pipers = []
        status = POpen4::popen4(command){|p_stdout, p_stderr, p_stdin, p_id|
          pid = p_id
          barrier.wait
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
          pipers << Thread.new{
            target = p_stdout
            timeout_count = 0
            while true
              begin
                if (ready = IO.select([target], [], [], 1))
                  ready.first.each do |fd|
                    buf = fd.read_nonblock(4096)
                    stdouts.each{|out| out.print buf}
                  end
                  Thread.exit if target.eof?
                else
                  if process_exited
                    timeout_count += 1
                    if timeout_count > 5
                      target.close_read
                      Thread.exit
                    end
                  end
                end
              rescue IOError => err
                if target.closed?
                  Thread.exit
                end
              end
            end
          }
          pipers << Thread.new{
            target = p_stderr
            timeout_count = 0
            while true
              begin
                if (ready = IO.select([target], [], [], 1))
                  ready.first.each do |fd|
                    buf = fd.read_nonblock(4096)
                    stderrs.each{|out| out.print buf}
                  end
                  Thread.exit if target.eof?
                else
                  if process_exited
                    timeout_count += 1
                    if timeout_count > 5
                      target.close_read
                      Thread.exit
                    end
                  end
                end
              rescue IOError => err
                if target.closed?
                  Thread.exit
                end
              end
            end
          }
          if options[:stdin]
            pipers << Thread.new{
            target = options[:stdin]
            timeout_count = 0
            while true
              begin
                if (ready = IO.select([target], [], [], 1))
                  ready.first.each do |fd|
                      buf = fd.read_nonblock(4096)
                      p_stdin.print buf
                    end
                else
                  if process_exited
                    timeout_count += 1
                    if timeout_count > 5
                      p_stdin.close_write
                      Thread.exit
                    end
                  end
                end
              rescue IOError => err
                if target.closed?
                  Thread.exit
                end
              end
            end
          }
          end
        }
        pipers.each{|t| t.join}
        raise ArgumentError.new("Invalid command: #{command}") unless status
        procdb_update_status(pid, status)
      }
      barrier.wait
      procdb_spawn(pid, command, t)
      timekeeper = nil

      killed = false
      timekeeper = nil
      if options[:timeout] > 0
        timekeeper = Thread.new do
          sleep(options[:timeout])
          begin
            Process.kill(:INT, pid)
            killed = true
          rescue Errno::ESRCH # No such process
          end
        end
      end
      if options[:wait]
        timekeeper.join if timekeeper
        t.join
        if (! killed) && options[:raise_failure] && status.exitstatus != 0
          raise RuntimeError.new("'#{command}' failed.")
        end
      end
      while ! pid
        sleep 0.001 # do nothing
      end

      pid
    end

    def with_process2(*args)
      options = (if args.last.is_a? Hash
                   args.pop
                 else
                   {}
                 end )
      options = {
        :kill_on_exit => false
      }.merge(options)
      
      command = args.flatten.map(&:to_s).join(" ")
      pid = Process.spawn(command)

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
          begin
            Process.kill(:TERM, pid)
          rescue Exception
          end
        else
          begin
            status = Process.waitpid(pid)
            p status
          rescue Errno::ESRCH
          end
        end
      end
      raise err if err
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
          begin
            Process.kill(:TERM, pid)
          rescue Exception
          end
        else
          procdb_waitpid(pid)
          status = procdb_get_status(pid)
          unless status && status.exitstatus == 0
            command = procdb_get_command(pid) || "Unknown command"
            raise RuntimeError.new("'#{command}' failed.")
          end
          procdb_resetpid(pid)
        end
      end

      raise err if err
    end

    def use_script(name)
      name = name.to_s
      name = name + ".rb" unless name =~ /\.rb$/
      dir = @plan.jkr_env.jkr_script_dir
      path = File.join(dir, name)
      script = File.open(path, "r").read
      self.instance_eval(script, path, 1)
      true
    end
  end

  class TrialUtils
    def self.undef_routine_utils(plan)
      plan.routine.binding.eval <<EOS
undef result_file
undef result_file_name
undef rname
undef common_file_name
undef cname
undef touch_result_file
undef with_result_file
EOS
    end

    def self.define_routine_utils(result_dir, plan, params)
      line = __LINE__; src = <<EOS
def result_file_name(basename)
  File.join(#{result_dir.inspect}, basename)
end
def rname(basename)
  result_file_name(basename)
end

def result_file(basename, mode = "a+")
  path = result_file_name(basename)
  File.open(path, mode)
end

def common_file_name(basename)
  File.join(File.dirname(#{result_dir.inspect}), basename)
end
def cname(basename)
  result_file_name(basename)
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
  }.sort
end

def result_file_name(num, basename)
  if num.is_a? Integer
    num = sprintf "%03d", num
  end
  File.join(#{resultset_dir.inspect}, num, basename)
end
def rname(num, basename)
  result_file_name(num, basename)
end

def result_file(num, basename, mode = "r")
  path = result_file_name(num, basename)
  File.open(path, mode)
end

def common_file_name(basename)
  File.join(#{resultset_dir.inspect}, basename)
end
def cname(basename)
  common_file_name(basename)
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
