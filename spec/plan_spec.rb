
require 'spec_helper'

describe Jkr::Plan do
  before(:each) do
    env_dir = File.expand_path("sample_env", FIXTURE_DIR)
    @jkr_env = Jkr::Env.new(env_dir)
    @plan = Jkr::Plan.new(@jkr_env, "example")

    $call_order = []
  end

  it "should load example.plan" do
    expect(@plan).not_to be_nil
    expect(@plan.title).to eq("example")
  end

  it "should respond to base_plan" do
    expect(@plan).to respond_to(:base_plan)
  end

  it "should have nil base_plan by default" do
    expect(@plan.base_plan).to eq(nil)
  end

  it "should respond to params" do
    expect(@plan).to respond_to(:params)
  end

  it "should have param :foo and its value is 123" do
    expect(@plan.params).to include(:foo)
    expect(@plan.params[:foo]).to eq(123)
  end

  it "should respond to param_names" do
    expect(@plan).to respond_to(:param_names)
  end

  it "should return all params by param_names" do
    expect(@plan.param_names.sort).to eq([:foo, :yomiko].sort)
  end

  it "should respond to vars" do
    expect(@plan).to respond_to(:params)
  end

  it "should have var :baz and its possible values are [:a, :b]" do
    expect(@plan.vars).to include(:baz)
    expect(@plan.vars[:baz]).to eq([:a, :b])
  end

  it "should respond to var_names" do
    expect(@plan).to respond_to(:var_names)
  end

  it "should return all vars by var_names" do
    expect(@plan.var_names.sort).to eq([:baz, :miss].sort)
  end

  it "should respond to do_prep" do
    expect(@plan.prep).to be_a(Proc)
    expect(@plan.do_prep).to eq("this is example.plan's prep")
  end

  it "should respond to do_routine" do
    expect(@plan.routine).to be_a(Proc)
    expect(@plan.do_routine(@plan, {})).to eq("this is example.plan's routine")
  end

  it "should respond to do_cleanup" do
    expect(@plan.cleanup).to be_a(Proc)
    expect(@plan.do_cleanup).to eq("this is example.plan's cleanup")
  end

  it "should respond to do_analysis" do
    expect(@plan.analysis).to be_a(Proc)
    expect(@plan.do_analysis).to eq("this is example.plan's analysis")
  end

  describe "do_prep" do
    it "should work with given plan" do
      @plan.prep = proc do |plan|
        @plan == plan
      end
      pseudo_plan = Object.new
      expect(@plan.do_prep(pseudo_plan)).to eq(false)
    end
  end

  describe "with plan inheritance" do
    before(:each) do
      @plan = Jkr::Plan.new(@jkr_env, "child_of_example")
    end

    it "should be a child of example" do
      expect(@plan.title).to eq("child of example")
    end

    it "should overwrite param :foo" do
      expect(@plan.params[:foo]).to eq(456)
    end

    it "should overwrite var :baz" do
      expect(@plan.vars[:baz]).to eq([:c, :d])
    end

    it "should return all params by param_names" do
      expect(@plan.param_names.sort).to eq([:foo, :yomiko].sort)
    end

    it "should return all vars by var_names" do
      expect(@plan.var_names.sort).to eq([:baz, :miss].sort)
    end

    it "should have base_plan" do
      expect(@plan).not_to be_nil
      expect(@plan.base_plan).to be_a(Jkr::Plan)
      expect(@plan.base_plan.title).to eq("example")
    end

    it "should call: base's prep -> child's prep" do
      $call_order = []
      expect(@plan.do_prep()).to eq("this is child_of_example.plan's prep")
      expect($call_order).to eq(["child_of_example", "example"])
    end

    it "should call: base's routine -> child's routine" do
      $call_order = []
      expect(@plan.do_routine(@plan, {})).to eq("this is child_of_example.plan's routine")
      expect($call_order).to eq(["child_of_example", "example"])
    end

    it "should call: base's cleanup -> child's cleanup" do
      $call_order = []
      expect(@plan.do_cleanup()).to eq("this is child_of_example.plan's cleanup")
      expect($call_order).to eq(["child_of_example", "example"])
    end

    it "should call: base's analysis -> child's analysis" do
      $call_order = []
      expect(@plan.do_analysis()).to eq("this is child_of_example.plan's analysis")
      expect($call_order).to eq(["child_of_example", "example"])
    end

    it "should raise error with param not defined in its base" do
      expect do
        Jkr::Plan.new(@jkr_env, "child_of_example_invalparam")
      end.to raise_error(Jkr::ParameterError)
    end

    it "should raise error with var not defined in its base" do
      expect do
        Jkr::Plan.new(@jkr_env, "child_of_example_invalvar")
      end.to raise_error(Jkr::ParameterError)
    end

    it "should raise error with param overwriting var" do
      expect do
        Jkr::Plan.new(@jkr_env, "child_of_example_val_param")
      end.to raise_error(Jkr::ParameterError)
    end

    it "should raise error with var overwriting param" do
      expect do
        Jkr::Plan.new(@jkr_env, "child_of_example_param_val")
      end.to raise_error(Jkr::ParameterError)
    end
  end

  it "should raise error with var overwriting param" do
    expect do
      Jkr::Plan.new(@jkr_env, "example_param_var")
    end.to raise_error(Jkr::ParameterError)
  end

  it "should raise error with const overwriting var" do
    expect do
      Jkr::Plan.new(@jkr_env, "example_var_param")
    end.to raise_error(Jkr::ParameterError)
  end

  describe "who is grandchild" do
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

      @plan = Jkr::Plan.new(@jkr_env, "grandchild")
    end

    it "should be able to load ancestors from specified dir" do
      tmp_plandir = Dir.mktmpdir
      FileUtils.copy(File.expand_path("parent.plan", @jkr_env.jkr_plan_dir),
                     tmp_plandir)
      FileUtils.copy(File.expand_path("child.plan", @jkr_env.jkr_plan_dir),
                     tmp_plandir)
      FileUtils.copy(File.expand_path("grandchild.plan", @jkr_env.jkr_plan_dir),
                     tmp_plandir)
      FileUtils.rm(File.expand_path("parent.plan", @jkr_env.jkr_plan_dir))
      FileUtils.rm(File.expand_path("child.plan", @jkr_env.jkr_plan_dir))
      FileUtils.rm(File.expand_path("grandchild.plan", @jkr_env.jkr_plan_dir))

      expect do
        Jkr::Plan.new(@jkr_env, nil,
                      :plan_path => File.expand_path("grandchild.plan", tmp_plandir),
                      :plan_search_path => tmp_plandir)
      end.to_not raise_error
    end
  end

end
