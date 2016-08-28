
module Jkr
  class SysInfo
    class << self
      def gather
        ret = Hash.new
        ret[:proc] = Hash.new

        # gather infomation under /proc
        ret[:proc][:cpuinfo] = `cat /proc/cpuinfo`
        ret[:proc][:meminfo] = `cat /proc/meminfo`
        ret[:proc][:interrupts] = `cat /proc/interrupts`
        ret[:proc][:mdstat] = `cat /proc/mdstat`
        ret[:proc][:mounts] = `cat /proc/mounts`

        ret[:sys] = Hash.new
        ret[:sys][:block] = Hash.new
        Dir.glob("/sys/block/*").each do |block_path|
          block = File.basename(block_path).to_sym
          ret[:sys][:block][block] = Hash.new
          ret[:sys][:block][block][:queue] = Hash.new
          Dir.glob("#{block_path}/queue/scheduler") do |path|
            ret[:sys][:block][block][:queue][:scheduler] = `cat #{path}`
          end
          Dir.glob("#{block_path}/queue/nr_requests") do |path|
            ret[:sys][:block][block][:queue][:nr_requests] = `cat #{path}`
          end
        end

        ret
      end
    end
  end
end
