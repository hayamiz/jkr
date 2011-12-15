
require 'pathname'

def rel_path(basefile, path)
  base = Pathname.new(File.dirname(basefile))
  path = Pathname.new(path)
  path.relative_path_from(base).to_s
end

def gnuplot_label_escape(str)
  ret = str.gsub(/_/, "\\\\\\_").gsub(/\{/, "\\{").gsub(/\}/, "\\}")
  ret
end

def plot_distribution(config)
  dataset = config[:dataset]
  xrange_max = config[:xrange_max]
  xrange_min = config[:xrange_min] || 0
  title = config[:title]
  xlabel = config[:xlabel]
  eps_file = config[:output]
  datafile = if config[:datafile]
               File.open(config[:datafile], "w")
             else
               Tempfile.new("dist")
             end
  if config[:gpfile]
    gpfile = File.open(config[:gpfile], "w")
  else
    gpfile = Tempfile.new("plot_dist")
  end
  datafile_path = rel_path(gpfile.path, datafile)

  stepnum = 500

  plot_stmt = []
  data_idx = 0
  xrange_max_local = 0
  histset = []
  dataset.each do |tx_type,data|
    next if data.empty?
    hist = Array.new
    avg = data.inject(&:+) / data.size.to_f
    sterr = data.sterr
    stdev = data.stdev
    n90th_idx = (data.size * 0.9).to_i
    n90percent = data.sort[n90th_idx]
    xrange_max_local = [xrange_max_local, xrange_max || n90percent * 4].max
    step = xrange_max_local / stepnum
    maxidx = 0
    data.each_with_index do |num, data_idx|
      idx = (num / step).to_i
      maxidx = [idx, maxidx].max
      hist[idx] = (hist[idx] || 0) + 1
    end

    0.upto(maxidx) do |idx|
      unless hist[idx]
        hist[idx] = 0
      end
    end

    histset.push({:tx_type => tx_type, :step => step, :hist => hist, :max => hist.max})

    histmax = hist.max.to_f
    datafile.puts "##{tx_type}"
    0.upto(stepnum - 1) do |i|
      x = (i + 0.5) * step
      y = hist[i] || 0
      if config[:normalize]
        y = y / histmax
      end
      datafile.puts "#{x}\t#{y}"
    end
    datafile.puts
    datafile.puts

# index data_idx+1
    datafile.puts "#{avg}\t0"
    datafile.puts "#{avg}\t#{hist.max * 1.2}"
    datafile.puts
    datafile.puts

# index data_idx+2
    datafile.puts "#{n90percent}\t0"
    datafile.puts "#{n90percent}\t#{hist.max * 1.2}"
    datafile.puts
    datafile.puts

# index data_idx+3
    datafile.puts "#{avg-sterr * 3}\t0"
    datafile.puts "#{avg-sterr * 3}\t#{hist.max * 1.2}"
    datafile.puts
    datafile.puts
# index data_idx+4
    datafile.puts "#{avg+sterr * 3}\t0"
    datafile.puts "#{avg+sterr * 3}\t#{hist.max * 1.2}"
    datafile.puts

    plot_stmt.push(sprintf("'%s' index %d:%d using 1:2 with linespoints title '%s'",
                           datafile_path, data_idx, data_idx, tx_type))
    if config[:show_avgline]
      plot_stmt.push(sprintf("'%s' index %d:%d using 1:2 with lines lc 1 lt 2 lw 3 title '%s(avg)'",
                             datafile_path, data_idx+1, data_idx+1, tx_type))
    end
    if config[:show_90pline]
      plot_stmt.push(sprintf("'%s' index %d:%d using 1:2 with lines lc 2 lt 2 lw 3 title '%s(90%%-th)'",
                             datafile_path, data_idx+2, data_idx+2, tx_type))
    end
    if config[:show_confinterval]
      plot_stmt.push(sprintf("'%s' index %d:%d using 1:2 with lines lc 3 lt 3 lw 3 title '%s(std err)'",
                             datafile_path, data_idx+3, data_idx+3, tx_type))
      plot_stmt.push(sprintf("'%s' index %d:%d using 1:2 with lines lc 3 lt 3 lw 3 title '%s(std err)'",
                             datafile_path, data_idx+4, data_idx+4, tx_type))
    end
    data_idx += 5
  end

  datafile.fsync
  plot_stmt = plot_stmt.flatten.join(", \\\n     ")
  plot_stmt = "plot #{plot_stmt}"

  script = <<EOS
set term postscript enhanced color
set output "#{rel_path(gpfile.path, eps_file)}"
set size 0.9,0.6
set title "#{gnuplot_label_escape(title)}"
set ylabel "Frequency"
set xlabel "#{gnuplot_label_escape(xlabel)}"
set xrange [#{xrange_min}:#{xrange_max_local}]
#{config[:other_options]}
#{plot_stmt}
EOS
  gpfile.puts script
  gpfile.fsync
  Dir.chdir(File.dirname(gpfile.path)) do
    system_("gnuplot #{gpfile.path}")
  end
  gpfile.close
end

def plot_timeseries(config)
  [:plot_data, :output, :title, :xlabel, :ylabel].each do |key|
    unless config[key]
      raise ArgumentError.new("key '#{key.to_s}' is required for time-series graph")
      return
    end
  end
  
  xrange = if config[:xrange]
             "set xrange #{config[:xrange]}"
           else
             ""
           end
  yrange = if config[:yrange]
             "set yrange #{config[:yrange]}"
           else
             ""
           end

  if config[:gpfile]
    gpfile = File.open(config[:gpfile], "w")
  else
    gpfile = Tempfile.new("plot_timeseries")
  end

  plot_stmt = "plot " + config[:plot_data].map {|plot_datum|
    [:datafile, :using, :with, :title].each do |key|
      unless plot_datum[key]
        raise ArgumentError.new("key '#{key.to_s}' is required for a plot_datum of time-series graph")
        return
      end
    end
    index = ""
    if plot_datum[:index]
      index = " index #{plot_datum[:index]} "
    end
    "'#{rel_path(gpfile.path, plot_datum[:datafile])}' #{index} using #{plot_datum[:using]} with #{plot_datum[:with]}"+
    " title '#{gnuplot_label_escape(plot_datum[:title])}' " + plot_datum[:other_options].to_s
  }.join(", \\\n     ")

  script = <<EOS
set term postscript enhanced color
set output "#{rel_path(gpfile.path, config[:output])}"
set size 0.9,0.6
set title "#{gnuplot_label_escape(config[:title])}"
set ylabel "#{config[:ylabel]}"
set xlabel "#{config[:xlabel]}"
set rmargin 3
set lmargin 10
#{xrange}
#{yrange}
set grid
#{config[:other_options]}
#{plot_stmt}
EOS
  gpfile.puts script
  gpfile.fsync
  Dir.chdir(File.dirname(gpfile.path)) do
    system_("gnuplot #{gpfile.path}")
  end
  gpfile.close
end

def plot_bar(config)
  [:output, :title, :series_labels, :item_labels, :data].each do |key|
    unless config[key]
      raise StandardError.new("key '#{key.to_s}' is required for bar graph")
    end
  end

  config[:size] ||= "0.9,0.6"

  data = config[:data]

  if ! data.all?{|series| series.all?{|datum| datum[:value].is_a? Numeric}}
    raise StandardError.new("All datum must have :value key")
  end

  if config[:datafile]
    datafile = File.open(config[:datafile], "w")
  else
    datafile = Tempfile.new("plot_bar")
  end
  if config[:gpfile]
    gpfile = File.open(config[:gpfile], "w")
  else
    gpfile = Tempfile.new("plot_bar")
  end
  datafile_path = rel_path(gpfile.path, datafile.path)

  config[:item_label_angle] ||= -30

  plot_data = []
  plot_stdev_data = []

  if data.all?{|series| series.all?{|datum| datum[:stdev].is_a? Numeric}}
    draw_stdev = true
  else
    draw_stdev = false
  end

  item_barwidth = 0.8 # 2.0 / 3.0
  num_serieses = data.size
  data_idx = 0
  config[:data].each_with_index do |series, series_idx|
    series.each_with_index do |datum, item_idx|
      xpos = item_idx - item_barwidth / 2.0 + item_barwidth / num_serieses.to_f / 2.0 + item_barwidth / num_serieses.to_f * series_idx
      barwidth = item_barwidth / num_serieses.to_f
      datafile.puts([xpos, datum[:value], barwidth, (datum[:stdev] || "")].join("\t"))
    end

    plot_data.push({
                     :title => config[:series_labels][series_idx],
                     :using => "1:2:3",
                     :index => "#{data_idx}:#{data_idx}",
                     :with => "with boxes fs solid 0.7",
                   })

    if series.every?{|datum| datum[:stdev]}
      plot_data.push({
                       :title => nil,
                       :using => "1:2:4",
                       :index => "#{data_idx}:#{data_idx}",
                       :with => "with yerrorbars lc 1 lt 1 pt 0",
                     })
    end

    datafile.puts("\n\n")
    data_idx += 1
  end
  datafile.fsync

  ylabel = if config[:ylabel]
             "set ylabel '#{config[:ylabel]}'"
           else
             ""
           end

  yrange = if config[:yrange]
             "set yrange #{config[:yrange]}"
           else
             ""
           end

  plot_stmt = "plot " + plot_data.map do |plot_datum|
    [:using].each do |key|
      unless plot_datum[key]
        raise StandardError.new("key '#{key.to_s}' is required for a plot_datum of bar graph")
        return
      end
    end
    index = ""
    if plot_datum[:index]
      index = " index #{plot_datum[:index]} "
    end
    if plot_datum[:title]
      title = "title '#{gnuplot_label_escape(plot_datum[:title])}'"
    else
      title = "notitle"
    end
    "'#{rel_path(gpfile.path, datafile.path)}' #{index} using #{plot_datum[:using]}"+
        " #{title} #{plot_datum[:with]} "
  end.join(", \\\n     ")

  xpos = -1
  xtics = config[:item_labels].map do |label|
    xpos += 1
    "\"#{label}\" #{xpos}"
  end.join(",")
  xtics = "(#{xtics})"
  xrange = "[-0.5:#{config[:item_labels].size - 0.5}]"

  script = <<EOS
set term postscript enhanced color
set output "#{rel_path(gpfile.path, config[:output])}"
set size #{config[:size]}
set title "#{gnuplot_label_escape(config[:title])}"
#{ylabel}
#{yrange}
set xrange #{xrange}
set xtic rotate by #{config[:item_label_angle]} scale 0
set xtics #{xtics}
#{config[:other_options]}
#{plot_stmt}
EOS
  gpfile.puts script
  gpfile.fsync
  Dir.chdir(File.dirname(gpfile.path)) do
    system_("gnuplot #{gpfile.path}")
  end
  gpfile.close
end

def plot_scatter(config)
  [:plot_data, :output, :xlabel, :ylabel].each do |key|
    unless config.keys.include?(key)
      raise ArgumentError.new("key '#{key.to_s}' is required for scatter graph")
    end
  end

  config[:size] ||= "0.9,0.7"

  xrange = if config[:xrange]
             "set xrange #{config[:xrange]}"
           else
             ""
           end
  yrange = if config[:yrange]
             "set yrange #{config[:yrange]}"
           else
             ""
           end
  if config[:gpfile]
    gpfile = File.open(config[:gpfile], "w")
  else
    gpfile = Tempfile.new("gnuplot")
  end

  plot_stmt = "plot " + config[:plot_data].map {|plot_datum|
    unless plot_datum[:expression] ||
        [:datafile, :using].every?{|key| plot_datum[key]}
      raise ArgumentError.new("key ('datafile', 'using', 'with') or 'expression' is required for a plot_datum")
    end

    plot_target = nil
    if plot_datum[:expression]
      plot_target = plot_datum[:expression]
    else
      index = ""
      if plot_datum[:index]
        index = " index #{plot_datum[:index]} "
      end

      plot_target = "'#{rel_path(gpfile.path, plot_datum[:datafile])}' #{index} using #{plot_datum[:using]}"
    end

    unless plot_datum[:title]
      title = "notitle"
    else
      title = "title '#{gnuplot_label_escape(plot_datum[:title])}'"
    end

    if plot_datum[:with]
      with = "with #{plot_datum[:with]}"
    else
      with = ""
    end
    "#{plot_target} #{with} #{title} " + plot_datum[:other_options].to_s
  }.join(", \\\n     ")

  title_stmt = "unset title"
  if config[:title]
    title_stmt = "set title \"#{gnuplot_label_escape(config[:title])}\""
  end

  script = <<EOS
set term postscript enhanced color
set output "#{rel_path(gpfile.path, config[:output])}"
set size #{config[:size]}
#{title_stmt}
set ylabel "#{gnuplot_label_escape(config[:ylabel])}"
set xlabel "#{gnuplot_label_escape(config[:xlabel])}"
set rmargin 10
set lmargin 10
#{xrange}
#{yrange}
set grid
#{config[:other_options]}
#{plot_stmt}
EOS
  gpfile.puts script
  gpfile.fsync
  Dir.chdir(File.dirname(gpfile.path)) do
    system_("gnuplot #{gpfile.path}")
  end
  gpfile.close
end

def plot_mpstat_data(mpstat_data, option)
  option[:dir] ||= "mpstat"
  option[:start_time] ||= mpstat_data.first[:time]
  option[:end_time] ||= mpstat_data[-1][:time]

  if ! Dir.exists?(option[:dir])
    FileUtils.mkdir_p(option[:dir])
  end

  datafile = File.open(File.join(option[:dir],
                                 "mpstat.tsv"),
                       "w")

  start_time = option[:start_time]
  end_time = option[:end_time]

  data_idx = 0
  nr_cpu = mpstat_data.first[:data].size - 1
  (nr_cpu + 1).times do |cpu_idx|
    scale = 1.0
    if cpu_idx < nr_cpu
      label = cpu_idx.to_s
    else
      label = "ALL"
      scale = nr_cpu.to_f
    end

    datafile.puts("# cpu#{label}")
    mpstat_data.each do |rec|
      t = rec[:time] - start_time

      if cpu_idx < nr_cpu
        data = rec[:data].find{|x| x[:cpu] == cpu_idx}
      else
        data = rec[:data].find{|x| x[:cpu] == "all"}
      end
      datafile.puts([t,
                     data[:usr] * scale,
                     data[:nice] * scale,
                     data[:sys] * scale,
                     data[:iowait] * scale,
                     data[:irq] * scale,
                     data[:soft] * scale,
                     data[:steal] * scale,
                     data[:idle] * scale].map(&:to_s).join("\t"))
    end
    datafile.puts("\n\n")
    datafile.fsync

    plot_scatter(:output => File.join(option[:dir],
                                      "cpu#{label}.eps"),
                 :gpfile => File.join(option[:dir],
                                      "gp_cpu#{label}.gp"),
                 :title => nil,
                 :xlabel => "elapsed time [sec]",
                 :ylabel => "CPU usage [%]",
                 :xrange => "[0:#{end_time - start_time}]",
                 :yrange => "[0:#{105 * scale}]",
                 :plot_data => [{
                                  :title => "%usr",
                                  :using => "1:2",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                },
                                {
                                  :title => "%nice",
                                  :using => "1:($2+$3)",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                },
                                {
                                  :title => "%sys",
                                  :using => "1:($2+$3+$4)",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                },
                                {
                                  :title => "%iowait",
                                  :using => "1:($2+$3+$4+$5)",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                },
                                {
                                  :title => "%irq",
                                  :using => "1:($2+$3+$4+$5+$6)",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                },
                                {
                                  :title => "%soft",
                                  :using => "1:($2+$3+$4+$5+$6+$7)",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                },
                                {
                                  :title => "%steal",
                                  :using => "1:($2+$3+$4+$5+$6+$7+$8)",
                                  :index => "#{data_idx}:#{data_idx}",
                                  :with => "filledcurve x1",
                                  :datafile => datafile.path
                                }].reverse,
                 :size => "0.9,0.9",
                 :other_options => <<EOS
set rmargin 3
set lmargin 5
set key below
EOS
                 )

    data_idx += 1
  end
end

def plot_io_pgr_data(pgr_data, option)
  option[:dir] ||= "io_pgr"
  option[:start_time] ||= pgr_data.first["time"]
  option[:end_time] ||= pgr_data[-1]["time"]

  if ! Dir.exists?(option[:dir])
    FileUtils.mkdir_p(option[:dir])
  end

  start_time = option[:start_time]
  end_time = option[:end_time]

  datafile = File.open(File.join(option[:dir],
                                 "io_pgr.tsv"),
                       "w")
  devices = pgr_data.first.keys.select do |key|
    key != "total" && pgr_data.first[key].is_a?(Hash)
  end

  devices.each do |device|
    do_read = false
    do_write = false
    unless pgr_data.all?{|rec| rec[device]['r/s'] < 0.1}
      do_read = true
    end
    unless pgr_data.all?{|rec| rec[device]['w/s'] < 0.1}
      do_read = true
    end

    if  do_read == false && do_write == false
      $stderr.puts("#{device} performs no I/O")
      next
    end

    datafile.puts("# #{device}")
    pgr_data.each do |rec|
      datafile.puts([rec["time"] - start_time,
                     rec[device]['r/s'],
                     rec[device]['w/s'],
                    ].map(&:to_s).join("\t"))
    end
    datafile.puts("\n\n")
    datafile.fsync

    plot_data = []
    if do_read
      plot_data.push({
                       :title => "read",
                       :datafile => datafile.path,
                       :using => "1:2",
                       :index => "0:0",
                       :with => "lines"
                     })
    end
    if do_write
      plot_data.push({
                       :title => "write",
                       :datafile => datafile.path,
                       :using => "1:3",
                       :index => "0:0",
                       :with => "lines"
                     })
    end

    plot_scatter(:output => File.join(option[:dir],
                                      device + ".eps"),
                 :gpfile => File.join(option[:dir],
                                      "gp_" + device + ".gp"),
                 :xlabel => "elapsed time [sec]",
                 :ylabel => "IOPS",
                 :xrange => "[0:#{end_time - start_time}]",
                 :yrange => "[0:]",
                 :title => "IO performance",
                 :plot_data => plot_data,
                 :other_options => <<EOS
set rmargin 3
set lmargin 10
set key below
EOS
                 )
  end
end
