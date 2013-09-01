
require 'spec_helper'

describe Jkr::Trial do
  it "should respond to run" do
    Jkr::Trial.should respond_to :run
  end

  describe "of grandchild plan" do
    before(:each) do
      @tmpdir = Dir.mktmpdir
      @env_dir = File.expand_path("test", @tmpdir)
      Dir.mkdir(@env_dir)
      @jkr_dir = File.expand_path("jkr", @env_dir)
      Dir.chdir(@env_dir) do
        system(File.expand_path("../../bin/jkr", __FILE__), "init")
      end
      @jkr_env = @jkr_env = Jkr::Env.new(@env_dir, @jkr_dir)

      FileUtils.copy(File.expand_path("parent.plan", FIXTURE_DIR),
                      @jkr_env.jkr_plan_dir)
      FileUtils.copy(File.expand_path("child.plan", FIXTURE_DIR),
                      @jkr_env.jkr_plan_dir)
      FileUtils.copy(File.expand_path("grandchild.plan", FIXTURE_DIR),
                      @jkr_env.jkr_plan_dir)

      @plan = Jkr::Plan.new(@jkr_env, "grandchild")
    end

    it "should create resultset dir by run" do
      @plan.resultset_dir.should be_nil
      Jkr::Trial.run(@jkr_env, @plan)
      # @plan.resultset_dir.should_not be_nil
      # File.directory?(@plan.resultset_dir).should be_true
    end

    it "should copy all ancestor plan files when run" do
      # Jkr::Trial.run(@jkr_env, @plan)
      # %w!parent.plan child.plan grandchild.plan!.each do |filename|
      #   File.exists?(File.expand_path(filename, @plan.resultset_dir)).should be_true
      # end
    end
  end
end

describe Jkr::TrialUtils do
  before(:each) do
    env_dir = File.expand_path("sample_env", FIXTURE_DIR)
    jkr_dir = File.expand_path("jkr", env_dir)
    @jkr_env = Jkr::Env.new(FIXTURE_DIR, jkr_dir)
    @plan = Jkr::Plan.new(@jkr_env, "example")
  end

  it "should define plan#result_file_name" do
    lambda do
      @plan.routine.binding.eval('result_file_name("foo")')
    end.should raise_error
    Jkr::TrialUtils.define_routine_utils('test_result_dir', @plan, {})
    lambda do
      @plan.routine.binding.eval('result_file_name("foo")')
    end.should_not raise_error
  end

  describe "with inheritance" do
    before(:each) do
      @plan = Jkr::Plan.new(@jkr_env, "child_of_example")
    end


    it "should devine plan$result_file_name for all ancestors" do
      Jkr::TrialUtils.define_routine_utils('test_result_dir', @plan, {})
      @plan.routine.binding.eval('result_file_name("foo")').should == 'test_result_dir/foo'
      @plan.base_plan.routine.binding.eval('result_file_name("foo")').should == 'test_result_dir/foo'
    end
  end
end
