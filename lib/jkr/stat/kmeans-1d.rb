
class Cluster1D
  attr_accessor :center, :points

  # Constructor with a starting centerpoint
  def initialize(center)
    @center = center
    @points = []
  end

  # Recenters the centroid point and removes all of the associated points
  def recenter!
    avg = 0
    old_center = @center

    # Sum up all x/y coords
    @points.each do |point|
      avg += point
    end

    # Average out data
    if points.length == 0
      avg = center
    else
      avg /= points.length
    end

    # Reset center and return distance moved
    @center = avg
    return (old_center - center).abs
  end
end

#
# kmeans algorithm
#

def kmeans1d(data, k, delta=0.001)
  clusters = []

  # Assign intial values for all clusters
  (1..k).each do |point|
    index = (data.length * rand).to_i

    rand_point = data[index]
    c = Cluster1D.new(rand_point)

    clusters.push c
  end

  # Loop
  while true
    # Assign points to clusters
    data.each do |point|
      min_dist = +Float::INFINITY
      min_cluster = nil

      # Find the closest cluster
      clusters.each do |cluster|
        dist = (point - cluster.center).abs

        if dist < min_dist
          min_dist = dist
          min_cluster = cluster
        end
      end

      # Add to closest cluster
      min_cluster.points.push point
    end

    # Check deltas
    max_delta = -Float::INFINITY

    clusters.each do |cluster|
      dist_moved = cluster.recenter!

      # Get largest delta
      if dist_moved > max_delta
        max_delta = dist_moved
      end
    end

    # Check exit condition
    if max_delta < delta
      return clusters
    end

    # Reset points for the next iteration
    clusters.each do |cluster|
      cluster.points = []
    end
  end
end
