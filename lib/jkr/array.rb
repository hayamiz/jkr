
class Array
  def sum()
    self.inject(&:+)
  end

  def avg()
    self.sum.to_f / self.size
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
end
