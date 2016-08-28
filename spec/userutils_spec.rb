
require 'spec_helper'

describe Jkr::DataUtils do
  describe "'read_top' class method" do
    before(:each) do
      @top_log = fixture_path("top.log")
    end

    it "should respond to :read_top" do
      expect(Jkr::DataUtils).to respond_to(:read_top)
    end

    it "should parse log file of top(3)" do
      top_data = Jkr::DataUtils.read_top(@top_log)
      expect(top_data.is_a?(Array)).to eq(true)
      top_data.each do |block|
        expect(block.is_a?(Array)).to eq(true)
        block.each do |record|
          expect(record.is_a?(Hash)).to eq(true)
        end
      end

      block = top_data.shift
      expect(block.size).to eq(162)
      record = block.shift
      now = Time.now
      expect(record[:time]).to eq(Time.new(now.year, now.month, now.day, 20, 38, 40))
      expect(record[:pid]).to eq(1305)
      expect(record[:user]).to eq("root")
      expect(record[:virt]).to eq(255 * 1024)
      expect(record[:res]).to eq(106 * 1024)
      expect(record[:shr]).to eq(6472)
      expect(record[:cpu]).to eq(2)
      expect(record[:mem]).to be_within(0.001).of(7.1)
      expect(record[:time_plus]).to be_within(0.001).of(9*60 + 52.34)
      expect(record[:command]).to eq("Xorg")

      record = block.shift
      {
        :time => Time.new(now.year, now.month, now.day, 20, 38, 40),
        :pid => 4400,
        :command => "gnome-terminal"
      }.each do |key, val|
        expect(record[key]).to eq(val)
      end

      block = top_data.shift
      record = block.shift
      expect(record[:time]).to eq(Time.new(now.year, now.month, now.day, 20, 38, 43))
    end

    it "should take :start_time option" do
      t = Time.at(0)
      top_data = Jkr::DataUtils.read_top(@top_log, :start_time => t)
      expect(top_data[0][0][:time]).to eq(Time.new(t.year, t.month, t.day, 20, 38, 40))

      t = Time.at(1234567)
      top_data = Jkr::DataUtils.read_top(@top_log, :start_time => t)
      expect(top_data[0][0][:time]).to eq(Time.new(t.year, t.month, t.day, 20, 38, 40))
    end

    it "should take :top_k option" do
      top_data = Jkr::DataUtils.read_top(@top_log, :top_k => 10)
      top_data.each do |block|
        expect(block.size).to eq(10)
      end
    end

    describe ":filter option" do
      it "should have buildin :kernel_process" do
        top_data = Jkr::DataUtils.read_top(@top_log,
                                           :filter => :kernel_process)
        block = top_data.first
        expect(block.size).to eq(151)
      end
    end
  end
end
