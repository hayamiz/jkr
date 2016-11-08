require 'spec_helper'

describe Jkr::Env do
  describe "with 'plain_env'" do
    before(:each) do
      @env_path = fixture_path("plain_env")
      @env = Jkr::Env.new(@env_path)
    end

    describe "constructor" do
      it "should raise an error with non-existent dir" do
        ridiculous_path = "/foo/bar/ababababa"

        expect(File.exists?(ridiculous_path)).to be_falsey
        expect do
          Jkr::Env.new(ridiculous_path)
        end.to raise_error(Errno::ENOENT)
      end

      it "should raise an error with empty dir" do
        tmpdir = Dir.mktmpdir

        expect do
          Jkr::Env.new(tmpdir)
        end.to raise_error(ArgumentError)
      end

      it "should succeed without any errors with an valid env dir" do
        env = nil
        expect do
          env = Jkr::Env.new(@env_path)
        end.not_to raise_error

        expect(env).to be_a(Jkr::Env)
      end
    end # constructor

    describe "'find_result' class method" do
      it "should return a correct result ID when a directory is an result directory" do
        ret_dir = File.expand_path("00001example", @env.jkr_result_dir)
        ret_sub_dir = File.expand_path("00001example/00000", @env.jkr_result_dir)

        expect(Jkr::Env.find_result(ret_dir)).to be(1)
        expect(Jkr::Env.find_result(ret_sub_dir)).to be(1)
      end

      it "should return nil when a directory is not a result directory" do
        expect(Jkr::Env.find_result(@env.jkr_dir)).to be_nil
      end
    end
  end
end
