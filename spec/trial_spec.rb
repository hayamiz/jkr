
require 'spec_helper'

describe Jkr::Trial do
  it "should respond to run" do
    expect(Jkr::Trial).to respond_to :run
  end

  describe "of grandchild plan" do
    before(:each) do
      @tmpdir = Dir.mktmpdir
      @env_dir = File.expand_path("test", @tmpdir)
      Dir.mkdir(@env_dir)
      Dir.chdir(@env_dir) do
        system(File.expand_path("../../exe/jkr", __FILE__), "init")
      end
      @jkr_env = @jkr_env = Jkr::Env.new(@env_dir)

      FileUtils.copy(File.expand_path("parent.plan", FIXTURE_DIR),
                     @jkr_env.jkr_plan_dir)
      FileUtils.copy(File.expand_path("child.plan", FIXTURE_DIR),
                     @jkr_env.jkr_plan_dir)
      FileUtils.copy(File.expand_path("grandchild.plan", FIXTURE_DIR),
                     @jkr_env.jkr_plan_dir)
      FileUtils.copy(File.expand_path("foo-bar-script.rb", FIXTURE_DIR),
                     @jkr_env.jkr_script_dir)

      @plan = Jkr::Plan.create_by_name(@jkr_env, "grandchild")
    end

    it "should create resultset dir by run" do
      expect(@plan.resultset_dir).to eq(nil)
      Jkr::Trial.run(@jkr_env, @plan)
      expect(@plan.resultset_dir).not_to eq(nil)
      expect(File.directory?(@plan.resultset_dir)).to eq(true)
    end

    it "should copy all ancestor plan files when run" do
      Jkr::Trial.run(@jkr_env, @plan)
      ['grandchild.plan',
       'plan/parent.plan', 'plan/child.plan',
       'script/foo-bar-script.rb'].each do |filename|
        expect(File).to exist(File.expand_path(filename, @plan.resultset_dir))
      end
    end
  end

  it "should save extending plans and used scripts" do
    env_dir = File.expand_path("use_extend_sample", FIXTURE_DIR)
    jkr_cmd = File.expand_path('../exe/jkr', __dir__)

    tmpdir = Dir.mktmpdir
    FileUtils.cp_r(env_dir, tmpdir)

    Dir.chdir("#{tmpdir}/#{File.basename(env_dir)}") do
      # run example.plan
      expect(system(jkr_cmd, "execute", "example")).to eq(true)

      # pick a result file
      ret_dir = Dir["./jkr/result/00000*"].first
      expect(ret_dir).not_to eq(nil)

      # check copied files
      ["example.plan", "plan/parent.plan", "script/example_script.rb"].each do |file|
        path = File.expand_path(file, ret_dir)
        expect(File).to exist(path)
      end
    end
  end
end

describe Jkr::TrialUtils do
  before(:each) do
    env_dir = File.expand_path("sample_env", FIXTURE_DIR)
    @jkr_env = Jkr::Env.new(env_dir)
    @plan = Jkr::Plan.create_by_name(@jkr_env, "example")
  end

  it "should define plan#result_file_name" do
    expect do
      @plan.routine.binding.eval('result_file_name("foo")')
    end.to raise_error(NoMethodError)

    Jkr::TrialUtils.define_routine_utils('test_result_dir', @plan, {})

    expect do
      @plan.routine.binding.eval('result_file_name("foo")')
    end.not_to raise_error
  end

  describe "with inheritance" do
    before(:each) do
      @plan = Jkr::Plan.create_by_name(@jkr_env, "child_of_example")
    end


    it "should devine plan$result_file_name for all ancestors" do
      Jkr::TrialUtils.define_routine_utils('test_result_dir', @plan, {})
      expect(@plan.routine.binding.eval('result_file_name("foo")')).to eq('test_result_dir/foo')
      expect(@plan.base_plan.routine.binding.eval('result_file_name("foo")')).to eq('test_result_dir/foo')
    end
  end
end
