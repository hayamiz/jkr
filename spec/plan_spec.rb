
require 'spec_helper'

describe Jkr::Plan do
  before(:each) do
    env_dir = File.expand_path("sample_env", FIXTURE_DIR)
    jkr_dir = File.expand_path("jkr", env_dir)
    @jkr_env = Jkr::Env.new(FIXTURE_DIR, jkr_dir)
    @plan = Jkr::Plan.new(@jkr_env, "example")

    $call_order = []
  end

  it "should load example.plan" do
    @plan.should_not be_nil
    @plan.title.should == "example"
  end

  it "should respond to base_plan" do
    @plan.should respond_to :base_plan
  end

  it "should have nil base_plan by default" do
    @plan.base_plan.should be_nil
  end

  it "should respond to params" do
    @plan.should respond_to :params
  end

  it "should have param :foo and its value is 123" do
    @plan.params.should include :foo
    @plan.params[:foo].should == 123
  end

  it "should respond to param_names" do
    @plan.should respond_to :param_names
  end

  it "should return all params by param_names" do
    @plan.param_names.sort.should == [:foo, :yomiko].sort
  end

  it "should respond to vars" do
    @plan.should respond_to :params
  end

  it "should have var :baz and its possible values are [:a, :b]" do
    @plan.vars.should include :baz
    @plan.vars[:baz].should == [:a, :b]
  end

  it "should respond to var_names" do
    @plan.should respond_to :var_names
  end

  it "should return all vars by var_names" do
    @plan.var_names.sort.should == [:baz, :miss].sort
  end

  it "should respond to do_prep" do
    @plan.prep.should be_a Proc
    @plan.do_prep.should == "this is example.plan's prep"
  end

  it "should respond to do_routine" do
    @plan.routine.should be_a Proc
    @plan.do_routine(@plan, {}).should == "this is example.plan's routine"
  end

  it "should respond to do_cleanup" do
    @plan.cleanup.should be_a Proc
    @plan.do_cleanup.should == "this is example.plan's cleanup"
  end

  it "should respond to do_analysis" do
    @plan.analysis.should be_a Proc
    @plan.do_analysis.should == "this is example.plan's analysis"
  end

  describe "do_prep" do
    it "should work with given plan" do
      @plan.prep = proc do |plan|
        @plan == plan
      end
      pseudo_plan = Object.new

      @plan.do_prep(pseudo_plan).should be_false
    end
  end

  describe "with plan inheritance" do
    before(:each) do
      @plan = Jkr::Plan.new(@jkr_env, "child_of_example")
    end

    it "should be a child of example" do
      @plan.title.should == "child of example"
    end

    it "should overwrite param :foo" do
      @plan.params[:foo].should == 456
    end

    it "should overwrite var :baz" do
      @plan.vars[:baz].should == [:c, :d]
    end

    it "should return all params by param_names" do
      @plan.param_names.sort.should == [:foo, :yomiko].sort
    end

    it "should return all vars by var_names" do
      @plan.var_names.sort.should == [:baz, :miss].sort
    end

    it "should have base_plan" do
      @plan.should_not be_nil
      @plan.base_plan.should be_a Jkr::Plan
      @plan.base_plan.title.should == "example"
    end

    it "should call: base's prep -> child's prep" do
      $call_order = []
      @plan.do_prep().should == "this is child_of_example.plan's prep"
      $call_order.should == ["example", "child_of_example"]
    end

    it "should call: base's routine -> child's routine" do
      $call_order = []
      @plan.do_routine(@plan, {}).should == "this is child_of_example.plan's routine"
      $call_order.should == ["example", "child_of_example"]
    end

    it "should call: base's cleanup -> child's cleanup" do
      $call_order = []
      @plan.do_cleanup().should == "this is child_of_example.plan's cleanup"
      $call_order.should == ["example", "child_of_example"]
    end

    it "should call: base's analysis -> child's analysis" do
      $call_order = []
      @plan.do_analysis().should == "this is child_of_example.plan's analysis"
      $call_order.should == ["example", "child_of_example"]
    end

    it "should raise error with param not defined in its base" do
      lambda do
        Jkr::Plan.new(@jkr_env, "child_of_example_invalparam")
      end.should raise_error(Jkr::ParameterError)
    end

    it "should raise error with var not defined in its base" do
      lambda do
        Jkr::Plan.new(@jkr_env, "child_of_example_invalvar")
      end.should raise_error(Jkr::ParameterError)
    end

    it "should raise error with param overwriting var" do
      lambda do
        Jkr::Plan.new(@jkr_env, "child_of_example_val_param")
      end.should raise_error(Jkr::ParameterError)
    end

    it "should raise error with var overwriting param" do
      lambda do
        Jkr::Plan.new(@jkr_env, "child_of_example_param_val")
      end.should raise_error(Jkr::ParameterError)
    end
  end

  it "should raise error with var overwriting param" do
    lambda do
      Jkr::Plan.new(@jkr_env, "example_param_var")
    end.should raise_error(Jkr::ParameterError)
  end

  it "should raise error with const overwriting var" do
    lambda do
      Jkr::Plan.new(@jkr_env, "example_var_param")
    end.should raise_error(Jkr::ParameterError)
  end
end
