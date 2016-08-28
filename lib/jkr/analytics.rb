
module Jkr
  class Analytics
    class << self
      def normalize_param(key, value = nil)
        if value.is_a? TrueClass
          return key.to_s + "_true"
        elsif value.is_a? FalseClass
          return key.to_s + "_false"
        end

        value
      end

      def each_group(results, variable, opt = {})
        # extract parameters given as variables
        param_keys = results.first[:params].keys.select do |param_key|
          values = results.map do |result|
            normalize_param(param_key, result[:params][param_key])
          end
          values.all?{|val| ! val.nil?} && values.sort.uniq.size > 1
        end

        unless param_keys.include?(variable)
          raise ArgumentError.new("Invalid variable: #{variable.inspect}")
        end
        [:start_time, :end_time].each do |obsolete_key|
          if param_keys.include?(obsolete_key)
            $stderr.puts("#{obsolete_key} should not be included in result[:params]")
            param_keys.delete(obsolete_key)
          end
        end
        param_keys.delete(:trial)
        param_keys.delete(variable)
        if opt[:except]
          opt[:except].each do |key|
            param_keys.delete(key)
          end
        end

        results.group_by do |result|
          param_keys.map{|key| normalize_param(key, result[:params][key])}
        end.sort_by do |group_param, group|
          group_param
        end.each do |group_param, group|
          group = group.sort_by{|result| result[:params][variable]}
          yield(group_param, group)
        end
      end

      def hton(str)
        if str.is_a? Numeric
          return str
        end

        units = {
          'k' => 1024, 'K' => 1024,
          'm' => 1024*1024, 'M' => 1024*1024,
          'g' => 1024*1024*1024, 'G' => 1024*1024*1024,
        }

        if str =~ /(\d+)([kKmMgG]?)/
          num = $1.to_i
          unit = $2
          if unit.size > 0
            num *= units[unit]
          end
        else
          raise ArgumentError.new("#{str} is not a valid number expression")
        end
        num
      end
    end
  end
end
