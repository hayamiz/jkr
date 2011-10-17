
require 'spec_helper'

ENV['RUBYLIB'] = File.expand_path('../../lib', __FILE__)
load File.expand_path('../../bin/jkr', __FILE__)

class DirFiles
  def initialize(dir)
    @dir = dir
  end

  def size
    Dir.glob(File.join(@dir, '*')).size
  end
end

def jkr(*argv)
  JkrCmd.new.dispatch(argv)
end

describe JkrCmd do
  before(:each) do
    @jkr_cmd = File.expand_path('../../bin/jkr', __FILE__)
  end

  it "should be executable" do
    (File::Stat.new(@jkr_cmd).mode & 0444).should == 0444
  end

  context "with temp dirs" do
    before(:each) do
      @tmpdir = Dir.mktmpdir
      @pwd = Dir.pwd
      Dir.chdir(@tmpdir)
    end

    describe "'list' subcommand" do
      it "should fail" do
        lambda do
          jkr("list")
        end.should raise_error
      end
    end

    describe "'run' subcommand" do
      it "should fail" do
        lambda do
          jkr("run")
        end
      end
    end

    describe "'init' subcommand" do
      it "should create skeleton dirs" do
        jkr("init").should be_true
        File.directory?(File.expand_path('jkr', @tmpdir)).should be_true
        File.directory?(File.expand_path('jkr/plan', @tmpdir)).should be_true
        File.directory?(File.expand_path('jkr/script', @tmpdir)).should be_true
        File.directory?(File.expand_path('jkr/result', @tmpdir)).should be_true
        File.directory?(File.expand_path('jkr/queue', @tmpdir)).should be_true
      end
    end

    context "with 'jkr' dir" do
      before(:each) do
        FileUtils.mkdir_p(File.expand_path('jkr/plan', @tmpdir))
        FileUtils.mkdir_p(File.expand_path('jkr/script', @tmpdir))
        FileUtils.mkdir_p(File.expand_path('jkr/result', @tmpdir))
        FileUtils.mkdir_p(File.expand_path('jkr/queue', @tmpdir))
      end

      after(:each) do
        FileUtils.remove_entry_secure('jkr')
      end

      describe "'list' subcommand" do
        it "should success" do
          jkr("list").should be_true
        end
      end
      
      context "with example plan" do
        before(:each) do
          FileUtils.copy(fixture_path('example.plan'), 'jkr/plan/')
        end

        it "should have no results at first" do
          Dir.glob('jkr/result/*').should be_empty
        end
        
        describe "'list' subcommand" do
          it "should include 'example' plan" do
            output = `#{@jkr_cmd} list`
            output.should include("example") #title
          end
        end
        
        describe "'run' subcommand" do
          it "should create a result dir" do
            lambda do
              jkr("run", "example").should be_true
            end.should change(DirFiles.new('jkr/result'), :size).by(1)

            dir = Dir.glob('jkr/result/*').first
            File.basename(dir).should == "00000example"
            File.exists?('jkr/result/00000example/00000/output.log').should be_true
            File.open('jkr/result/00000example/00000/output.log').read.should include("hello world")
          end
        end

        describe "'queue' subcommand" do
          it "should success" do
            jkr("queue", "example").should be_true
          end

          it "should copy a plan file into queue dir" do
            jkr("queue", "example").should be_true

            Dir.glob('jkr/queue/*').size.should == 1
            dir = Dir.glob('jkr/queue/*').sort.first
            File.basename(dir).should == "00000.example.plan"

            jkr("queue", "example").should be_true
            Dir.glob('jkr/queue/*').size.should == 2
            dir = Dir.glob('jkr/queue/*').sort[1]
            File.basename(dir).should == "00001.example.plan"
          end

          context "'run' after 'queue'" do
            before(:each) do
              jkr("queue", "example")
              jkr("queue", "example")
            end

            it "should run queued plans" do
              lambda do
                lambda do
                  jkr("run").should be_true
                end.should change(DirFiles.new('jkr/queue'), :size).by(-2)
              end.should change(DirFiles.new('jkr/result'), :size).by(2)

              File.exists?('jkr/result/00000example/example.plan').should be_true
              File.exists?('jkr/result/00001example/example.plan').should be_true

              File.read('jkr/result/00000example/00000/output.log').should include('hello world')
              File.read('jkr/result/00001example/00000/output.log').should include('hello world')
            end
          end

          context "under high-contention" do
            it "should queue 1000 plans correctly" do
              lambda do
                threads = (1..10).map do
                  Thread.new do
                    100.times do
                      jkr("queue", "example")
                    end
                  end
                end
                threads.map(&:join)
              end.should change(DirFiles.new('jkr/queue'), :size).by(1000)
            end
          end
        end
      end
    end

    after(:each) do
      Dir.chdir(@pwd)
      FileUtils.remove_entry_secure(@tmpdir)
    end
  end
end
