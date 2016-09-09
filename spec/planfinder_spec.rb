
require 'spec_helper'

describe Jkr::PlanFinder do
  before(:each) do
    env_dir = File.expand_path("sample_env", FIXTURE_DIR)
    @jkr_env = Jkr::Env.new(env_dir)
    @finder = Jkr::PlanFinder(@jkr_env)

    @example_plan_path = File.expand_path("sample_env/jkr/plan/example.plan", FIXTURE_DIR)
  end

  describe "#find method" do
    it "should find example.plan with plan name 'example'" do
      expect(@finder.find("example")).to eq(@example_plan_path)
    end

    it "should raise Errno::ENOENT with unknown plan name" do
      expect do
        @finder.find("kanchi")
      end.to raise_error(Errno::ENOENT)
    end
  end
end
