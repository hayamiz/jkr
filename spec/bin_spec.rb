
require 'spec_helper'

ENV['RUBYLIB'] = File.expand_path('../../lib', __FILE__)

class DirFiles
  def initialize(dir)
    @dir = dir
  end

  def size
    Dir.glob(File.join(@dir, '*')).size
  end
end

describe Jkr::CLI do
  before(:each) do
    @jkr_cmd = File.expand_path('../../exe/jkr', __FILE__)
  end

  def jkr(*argv)
    if argv.last.is_a? Hash
      opts = argv.pop
    else
      opts = {}
    end

    system("#{@jkr_cmd}", *argv, opts)
  end

  it "should be executable" do
    expect((File::Stat.new(@jkr_cmd).mode & 0444)).to eq(0444)
  end

  context "with temp dirs" do
    before(:each) do
      @tmpdir = Dir.mktmpdir
      @pwd = Dir.pwd
      Dir.chdir(@tmpdir)
    end

    describe "'list' subcommand" do
      it "should fail" do
        expect(jkr("list", :err => "/dev/null")).to eq(false)
      end
    end

    describe "'execute' subcommand" do
      it "should fail" do
        expect(jkr("execute", :err => "/dev/null")).to eq(false)
      end
    end

    describe "'init' subcommand" do
      it "should create skeleton dirs" do
        expect(jkr("init", :out => "/dev/null")).to eq(true)

        ['jkr', 'jkr/plan', 'jkr/result'].each do |dirname|
          expect(File.directory?(File.expand_path('jkr', @tmpdir))).to eq(true)
        end
      end
    end

    context "with 'jkr' dir" do
      before(:each) do
        FileUtils.mkdir_p(File.expand_path('jkr/plan', @tmpdir))
        FileUtils.mkdir_p(File.expand_path('jkr/script', @tmpdir))
        FileUtils.mkdir_p(File.expand_path('jkr/result', @tmpdir))
      end

      after(:each) do
        FileUtils.remove_entry_secure('jkr')
      end

      describe "'list' subcommand" do
        it "should success" do
          expect(jkr("list", :out => "/dev/null")).to eq(true)
        end
      end

      context "with example plan" do
        before(:each) do
          FileUtils.copy(fixture_path('example.plan'), 'jkr/plan/')
        end

        it "should have no results at first" do
          expect(Dir.glob('jkr/result/*')).to be_empty
        end

        describe "'list' subcommand" do
          it "should include 'example' plan" do
            output = `#{@jkr_cmd} list`
            expect(output).to include("example") #title
          end
        end

        describe "'execute' subcommand" do
          it "should create a result dir" do
            expect do
              expect(system("#{@jkr_cmd} execute example")).to eq(true)
            end.to change(DirFiles.new('jkr/result'), :size).by(1)

            dir = Dir.glob('jkr/result/*').first
            expect(File.basename(dir)).to eq("00000example")
            expect(File.exists?('jkr/result/00000example/00000/output.log')).to eq(true)
            expect(File.open('jkr/result/00000example/00000/output.log').read).to include("hello world")
          end
        end

        describe "'queue' subcommand" do
          skip "is skipped" do
          it "should success" do
            expect(jkr("queue", "example")).to eq(true)
          end

          it "should copy a plan file into queue dir" do
            expect(jkr("queue", "example")).to eq(true)

            expect(Dir.glob('jkr/queue/*').size).to eq(1)
            dir = Dir.glob('jkr/queue/*').sort.first
            expect(File.basename(dir)).to eq("00000.example.plan")

            expect(jkr("queue", "example")).to eq(true)
            expect(Dir.glob('jkr/queue/*').size).to eq(2)
            dir = Dir.glob('jkr/queue/*').sort[1]
            expect(File.basename(dir)).to eq("00001.example.plan")
          end

          context "'execute' after 'queue'" do
            before(:each) do
              jkr("queue", "example")
              jkr("queue", "example")
            end

            it "should execute queued plans" do
              expect do
                expect do
                  expect(jkr("execute")).to eq(true)
                end.to change(DirFiles.new('jkr/queue'), :size).by(-2)
              end.to change(DirFiles.new('jkr/result'), :size).by(2)

              expect(File.exists?('jkr/result/00000example/example.plan')).to eq(true)
              expect(File.exists?('jkr/result/00001example/example.plan')).to eq(true)

              expect(File.read('jkr/result/00000example/00000/output.log')).to include('hello world')
              expect(File.read('jkr/result/00001example/00000/output.log')).to include('hello world')
            end
          end
          end
          # context "under high-contention" do
          #   it "should queue 1000 plans correctly" do
          #     expect do
          #       threads = (1..10).map do
          #         Thread.new do
          #           100.times do
          #             jkr("queue", "example")
          #           end
          #         end
          #       end
          #       threads.map(&:join)
          #     end.to change(DirFiles.new('jkr/queue'), :size).by(1000)
          #   end
          # end
        end
      end
    end

    after(:each) do
      Dir.chdir(@pwd)
      FileUtils.remove_entry_secure(@tmpdir)
    end
  end
end
