
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
      @plan.resultset_dir.should_not be_nil
      File.directory?(@plan.resultset_dir).should be_true
    end

    it "should copy all ancestor plan files when run" do
      Jkr::Trial.run(@jkr_env, @plan)
      %w!parent.plan child.plan grandchild.plan!.each do |filename|
        File.exists?(File.expand_path(filename, @plan.resultset_dir)).should be_true
      end
    end
  end
end
