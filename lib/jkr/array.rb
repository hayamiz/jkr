
class Array
  def sum()
    self.inject(&:+)
  end

  def avg()
    if self.empty?
      nil
    else
      self.sum.to_f / self.size
    end
  end

  def stdev()
    avg = self.avg
    var = self.map{|val| (val - avg) ** 2}.sum
    if self.size > 1
      var /= self.size - 1
    end
    Math.sqrt(var)
  end

  def sterr()
    self.stdev / Math.sqrt(self.size)
  end

  def every?(&block)
    ret = true
    self.each do |elem|
      unless block.call(elem)
        ret = false
        break
      end
    end
    ret
  end

  def any?(&block)
    ret = false
    self.each do |elem|
      if block.call(elem)
        ret = true
        break
      end
    end
    ret
  end

  def group_by()
    ret = Hash.new{ Array.new }
    self.each do |elem|
      ret[yield(elem)] += [elem]
    end

    ret
  end
end
