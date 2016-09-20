
require 'spec_helper'

describe Jkr::PlanFinder do
  before(:each) do
    tmpdir = Dir.mktmpdir
    FileUtils.cp_r(File.expand_path("sample_env", FIXTURE_DIR), tmpdir)
    @env_dir = File.expand_path("sample_env", tmpdir)
    @jkr_env = Jkr::Env.new(@env_dir)
    @finder = Jkr::PlanFinder.new(@jkr_env)

    @example_plan_path = File.expand_path("jkr/plan/example.plan", @env_dir)
  end

  describe "#find_* method" do
    it "should find example.plan with plan name 'example'" do
      expect(@finder.find_by_name("example")).to eq(@example_plan_path)
    end

    it "should find plan with specified search path" do
      parent_plan_path = File.expand_path("parent.plan", FIXTURE_DIR)

      expect(@finder.find_by_name("parent",
                                  :plan_search_path => [FIXTURE_DIR])).to eq(parent_plan_path)
    end

    it "should find executed.plan with result id" do
      executed_plan_path = File.expand_path("jkr/result/00001executed/executed.plan", @env_dir)

      # make result dir and pseudo plan file
      FileUtils.mkdir_p(File.expand_path("jkr/result/00001executed", @env_dir))
      FileUtils.cp(@example_plan_path,
                   File.expand_path("jkr/result/00001executed/executed.plan", @env_dir))

      expect(@finder.find_by_result_id(1)).to eq(executed_plan_path)
    end

    it "should return nil with unknown plan name" do
      expect(@finder.find_by_name("kanchi")).to eq(nil)
    end
  end
end
