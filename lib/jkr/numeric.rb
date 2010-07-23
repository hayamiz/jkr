
class Integer
  def to_hstr
    if self < 2**10
      self.to_s
    elsif self < 2**20
      sprintf('%dK', self / 2**10)
    elsif self < 2**30
      sprintf('%dM', self / 2**20)
    else
      sprintf('%dG', self / 2**30)
    end
  end
end

class Float
  def to_hstr
    if self < 2**10
      sprintf('%.2f', self)
    elsif self < 2**20
      sprintf('%.2fK', self / 2**10)
    elsif self < 2**30
      sprintf('%.2fM', self / 2**20)
    else
      sprintf('%.2fG', self / 2**30)
    end
  end
end
