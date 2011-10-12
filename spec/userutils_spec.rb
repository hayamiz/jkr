
require 'spec_helper'

describe Jkr::DataUtils do
  describe "'read_top' class method" do
    before(:each) do
      @top_log = fixture_path("top.log")
    end

    it "should respond to :read_top" do
      Jkr::DataUtils.should respond_to(:read_top)
    end

    it "should parse log file of top(3)" do
      top_data = Jkr::DataUtils.read_top(@top_log)
      top_data.is_a?(Array).should be_true
      top_data.each do |block|
        block.is_a?(Array).should be_true
        block.each do |record|
          record.is_a?(Hash).should be_true
        end
      end

      block = top_data.shift
      block.size.should == 162
      record = block.shift
      now = Time.now
      record[:time].should == Time.new(now.year, now.month, now.day, 20, 38, 40)
      record[:pid].should == 1305
      record[:user].should == "root"
      record[:virt].should == 255 * 1024
      record[:res].should == 106 * 1024
      record[:shr].should == 6472
      record[:cpu].should == 2
      record[:mem].should be_within(0.001).of(7.1)
      record[:time_plus].should be_within(0.001).of(9*60 + 52.34)
      record[:command].should == "Xorg"

      record = block.shift
      {
        :time => Time.new(now.year, now.month, now.day, 20, 38, 40),
        :pid => 4400,
        :command => "gnome-terminal"
      }.each do |key, val|
        record[key].should == val
      end

      block = top_data.shift
      record = block.shift
      record[:time].should == Time.new(now.year, now.month, now.day, 20, 38, 43)
    end

    it "should take :start_time option" do
      t = Time.at(0)
      top_data = Jkr::DataUtils.read_top(@top_log, :start_time => t)
      top_data[0][0][:time].should == Time.new(t.year, t.month, t.day, 20, 38, 40)

      t = Time.at(1234567)
      top_data = Jkr::DataUtils.read_top(@top_log, :start_time => t)
      top_data[0][0][:time].should == Time.new(t.year, t.month, t.day, 20, 38, 40)
    end

    it "should take :top_k option" do
      top_data = Jkr::DataUtils.read_top(@top_log, :top_k => 10)
      top_data.each do |block|
        block.size.should == 10
      end
    end

    describe ":filter option" do
      it "should have buildin :kernel_process" do
        top_data = Jkr::DataUtils.read_top(@top_log,
                                           :filter => :kernel_process)
        block = top_data.first
        block.size.should == 151
      end
    end
  end
end
