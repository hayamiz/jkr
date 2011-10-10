
class Jkr
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
      if Dir.glob(input_basename + ".blktrace.*").size == 0
        raise ArgumentError.new("No such blktrace data: #{input_basename}")
      end
      @input_basename = input_basename
    end

    def raw_each(option = {}, &block)
      if option[:limit]
        limit = "| head -n #{option[:limit]}"
      else
        limit = ""
      end
      IO.popen("blkparse -f \"bt\\t%c\\t%s\\t%T.%t\\t%a\\t%d\\t%S\\t%n\\n\" -i #{@input_basename} #{limit} | grep '^bt'|sort -k4,4", "r") do |io|
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

      if option[:cache] && File.exists?(@input_basename + ".cache")
        records = Marshal.load(File.open(@input_basename + ".cache"))
      else
        records = []
        issues = []
        IO.popen("blkparse -f \"bt\\t%c\\t%s\\t%T.%t\\t%a\\t%d\\t%S\\t%n\\n\" -i #{@input_basename} #{limit} | grep '^bt'|sort -k4,4", "r") do |io|
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
        File.open(@input_basename + ".cache", "w") do |file|
          Marshal.dump(records, file)
        end
      end

      records.map do |*record|
        block.call(*record)
      end
    end
  end
end
