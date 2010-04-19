
require 'fileutils'
require 'popen4'

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
        :stdin  => nil,
        :stdout => [$stdout],
        :stderr => [$stderr]
      }.merge(options)

      pid = nil
      status = nil
      args.flatten!
      t = Thread.new do
        status = POpen4::popen4(args.join(" ")) do |p_stdout, p_stderr, p_stdin, p_id|
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
      if options[:wait]
        t.join
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
        Process.waitpid(pid)
      end
    end
  end

  class SysUtils
    def self.cpu_cores()
      `grep "core id" /proc/cpuinfo|wc -l`.to_i
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
