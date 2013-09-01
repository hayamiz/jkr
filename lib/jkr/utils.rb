
require 'fileutils'
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
    def use_script(name)
      $LOAD_PATH.push(@plan.jkr_env.jkr_script_dir)
      require name.to_s
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
