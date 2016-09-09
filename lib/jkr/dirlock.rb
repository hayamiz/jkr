
module Jkr
  class Dir
    def self.lock(dir_path)
      File.open(dir_path, "r") do |f|
        f.flock(File::LOCK_EX)
        yield
      end
    end
  end
end
