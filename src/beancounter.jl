# profile based on logs

# julia ./beancounter.jl <destination>

const destination = ARGS[1]

using Gadfly, Colors, Statistics
import Cairo

log_tar_gz = joinpath(destination,"logs.tar.gz")

### profile chart
data = String[]
open(`ls`)  ### hack for julia 0.6
open(`tar xzfO $log_tar_gz`) do stream 
  while ~eof(stream)
    line = readline(stream,keep=true)
    occursin("took", line) && push!(data,line)
  end
end

for var in ["reading input tile", "initializing", "transforming", "saving output tiles", "waiting", "overall",
            "peons", "squatters", "merging",
            "copying / moving single", "merging multiple", "clearing multiple", "reading multiple", "max'ing multiple", "deleting multiple", "writing multiple",
            "clearing octree", "downsampling octree", "saving octree"]
  idx = map(x->occursin(Regex(".*"*var*".*"),x), data)
  any(idx) || continue
  var2 = replace(var," " =>"_")
  @eval $(Symbol(var2*"_data")) =
        map(x->(m=match(r"[0-9.]*(?= sec)", x); parse(Float64, "0"*m.match)), $data[$idx])
  @eval $(Symbol(var2*"_q")) = quantile($(Symbol(var2*"_data")),[0.25,0.50,0.75])
  @eval $(Symbol(var2*"_n")) = length($(Symbol(var2*"_data")))
  @eval $(Symbol(var2*"_max")) = maximum($(Symbol(var2*"_data")))
  @eval $(Symbol(var2*"_min")) = minimum($(Symbol(var2*"_data")))
  @eval $(Symbol(var2*"_sum")) = sum($(Symbol(var2*"_data")))
end

plots=Plot[]

x = ["reading input tile", "initializing", "transforming", "saving output tiles", "waiting",
     "copying / moving single", "merging multiple", "clearing multiple", "reading multiple", "max'ing multiple", "deleting multiple", "writing multiple",
     "clearing octree", "downsampling octree", "saving octree"]
y = map(x->replace(x," " =>"_")*"_sum", x)
y = [@eval $(Symbol(x)) for x in y]
push!(plots, plot(x=x, y=y./3600, Geom.bar,
      Guide.xlabel(""), Guide.ylabel("CPU time (hr)"), Guide.title(basename(destination)),
      color=[fill("leaf",5)...;fill("merge",7)...;fill("octree",3)...],
      Scale.color_discrete_manual("red","green","blue")))


if !success(pipeline(`tar tf $log_tar_gz`,`grep monitor.log`))
  draw(PDF(joinpath(destination,"beancounter.pdf"), 4inch, 3inch), plots[1])
  exit()
end


### resource usage over time
units = Dict('B'=>1', 'K'=>10^3, 'M'=>10^6, 'G'=>10^9)

data = Dict{String,Matrix{Float32}}()
open(`tar xzfO $(joinpath(destination,"logs.tar.gz")) monitor.log`) do stream 
  while ~eof(stream)
    line = readline(stream,keep=true)
    fields = split(line)
    length(fields)==12 || continue
    node = fields[2]
    datum = map(field -> in(field,["-","--M"]) ? NaN :
        units[field[end]] * parse(Float32,field[1:end-1]), fields[[4,6,8,9,10]])
    push!(datum, map(field -> parse(Float32,field), fields[[11,12]])...)
    if haskey(data,node)
      data[node] = vcat(data[node], datum')
    else
      data[node] = datum'
    end
  end
end

idx=7; label="# tile-channels"
ydata=Float32[]
for node in keys(data)
  if isempty(ydata)
    ydata = data[node][:,idx]
  elseif length(ydata) < size(data[node],1)
    push!(ydata, zeros(Float32,size(data[node],1)-length(ydata))...)
    ydata += data[node][:,idx]
  elseif length(ydata) > size(data[node],1)
    ydata[1:size(data[node],1)] += data[node][:,idx]
  end
end
push!(plots, plot(y=ydata, Geom.line, Theme(default_color=colorant"black"),
      Guide.xlabel("time"), Guide.ylabel(label)))

colors=colormap("RdBu",length(data))

for (idx, label) in [(1,"RAM (GB)"), (6,"CPU (%)"), (2,"swap (GB)"), (3,"scratch (GB)")]
  layers=[]
  xmax=0;
  for (node,color) in zip(keys(data),colors)
    xmax = max(xmax,size(data[node],1))
    toGB = idx==6 ? 1.0 : 1024^3
    push!(layers, layer(y=data[node][:,idx]/toGB, Geom.line, Theme(default_color=color)))
  end
  push!(plots, plot(layers..., Guide.xlabel("time"), Guide.ylabel(label)))
end

draw(PDF(joinpath(destination,"beancounter.pdf"), 3*4inch, 2*3inch), gridstack(reshape(plots,2,3)))
