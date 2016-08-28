
module Jkr
  class Blktrace
    class << self
      def open(input_basename)
        self.new(input_basename)
      end

      def each(input_basename, &block)
        self.new(input_basename).each(&block)
      end
    end

    def initialize(input_basename)
      input_basename = Pathname.new(input_basename).relative_path_from(Pathname.new(`pwd`.strip)).to_s
      if Dir.glob(input_basename + ".blktrace.*").size > 0
        @input_basename = input_basename
        puts "multi file: #{input_basename}"
      else
        if File.exists?(input_basename)
          @input_singlefile = input_basename
          puts "single file: #{input_basename}"
        else
          raise ArgumentError.new("No such blktrace data: #{input_basename}")
        end
      end
    end

    def raw_each(option = {}, &block)
      if option[:limit]
        limit = "| head -n #{option[:limit]}"
      else
        limit = ""
      end
      if @input_basename
        cmd = "blkparse -f \"bt\\t%c\\t%s\\t%T.%t\\t%a\\t%d\\t%S\\t%n\\n\" -i #{@input_basename} #{limit} | grep '^bt'|sort -k4,4"
      elsif @input_singlefile
        cmd = "cat #{@input_singlefile}|blkparse -f \"bt\\t%c\\t%s\\t%T.%t\\t%a\\t%d\\t%S\\t%n\\n\" -i - #{limit} | grep '^bt'|sort -k4,4"
      end
      IO.popen(cmd, "r") do |io|
        while line = io.gets
          _, cpu, seqno, time, action, rwbs, pos_sec, sz_sec = line.split("\t")
          cpu = cpu.to_i
          seqno = seqno.to_i
          time = time.to_f
          pos_sec = pos_sec.to_i
          sz_sec = sz_sec.to_i
          record = [cpu, seqno, time, action, rwbs, pos_sec, sz_sec]

          block.call(record)
        end
      end
    end

    def each(option = {}, &block)
      self.map(option, &block)
      true
    end

    def map(option = {}, &block)
      if ! option.include?(:cache)
        option[:cache] = true
      end
      if option[:limit]
        limit = "| head -n #{option[:limit]}"
      else
        limit = ""
      end

      if @input_basename
        cache_file_path = @input_basename + ".cache"
      else
        cache_file_path = @input_singlefile + ".cache"
      end

      if option[:cache] && File.exists?(cache_file_path)
        records = Marshal.load(File.open(cache_file_path))
      else
        records = []
        issues = []
        if @input_basename
          cmd = "blkparse -f \"bt\\t%c\\t%s\\t%T.%t\\t%a\\t%d\\t%S\\t%n\\n\" -i #{@input_basename} #{limit} | grep '^bt'|sort -k4,4"
        elsif
          cmd = "cat #{@input_singlefile}|blkparse -f \"bt\\t%c\\t%s\\t%T.%t\\t%a\\t%d\\t%S\\t%n\\n\" -i - #{limit} | grep '^bt'|sort -k4,4"
        end
        IO.popen(cmd, "r") do |io|
          while line = io.gets
            _, cpu, seqno, time, action, rwbs, pos_sec, sz_sec = line.split("\t")
            cpu = cpu.to_i
            seqno = seqno.to_i
            time = time.to_f
            pos_sec = pos_sec.to_i
            sz_sec = sz_sec.to_i
            
            record = [cpu, seqno, time, action, rwbs, pos_sec, sz_sec]
            if action == "D"
              issues.push(record)
            elsif action == "C"
              # check pos and sz
              del_idx = nil
              issues.each_with_index do |rec, idx|
                if pos_sec == rec[5] && sz_sec == rec[6]
                  del_idx = idx
                  rt = time - rec[2]
                  record.push(rt) # append response time
                  records.push(record)
                  break
                end
              end
              if del_idx.nil?
                puts("Unmatched complete record: #{record.inspect}")
                # raise StandardError.new("Unmatched complete record: #{record.inspect}")
                next
              end
              issues.delete_at(del_idx)
            else
              raise NotImplementedError.new("Action #{action} handler is not implemented.")
            end
          end
        end
        File.open(cache_file_path, "w") do |file|
          Marshal.dump(records, file)
        end
      end

      records.map do |*record|
        block.call(*record)
      end
    end
  end
end
