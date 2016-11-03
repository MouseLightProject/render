# profile based on logs

# julia ./beancounter.jl <destination>

data = String[]
stream = open(`tar xzfO $(joinpath(ARGS[1],"logs.tar.gz"))`)[1]
while ~eof(stream)
  line = readline(stream)
  contains(line,"took") && push!(data,line)
end

for var in ["reading input tile", "initializing", "transforming", "saving output tiles", "waiting", "overall",
            "peons", "squatters", "merging",
            "copying single", "merging multiple", "clearing multiple", "reading multiple", "max'ing multiple", "deleting multiple", "writing multiple",
            "clearing octree", "downsampling octree", "saving octree"]
  idx = map(x->ismatch(Regex(".*"*var*".*"),x), data)
  any(idx) || continue
  var2 = replace(var," ","_")
  @eval $(Symbol(var2*"_data")) =
        map(x->(m=match(r"[0-9.]*(?= sec)", x); parse(Float64, "0"*m.match)), $data[$idx])
  @eval $(Symbol(var2*"_q")) = quantile($(Symbol(var2*"_data")),[0.25,0.50,0.75])
  @eval $(Symbol(var2*"_n")) = length($(Symbol(var2*"_data")))
  @eval $(Symbol(var2*"_max")) = maximum($(Symbol(var2*"_data")))
  @eval $(Symbol(var2*"_min")) = minimum($(Symbol(var2*"_data")))
  @eval $(Symbol(var2*"_sum")) = sum($(Symbol(var2*"_data")))
  @eval println($var2*" took ",signif($(Symbol(var2*"_sum")),4)," sec, n=",$(Symbol(var2*"_n")))
  #@eval println($var*" took ",$(Symbol(var*"_min")),", ",$(Symbol(var*"_q")),", ",$(Symbol(var*"_max"))," sec, n=",$(Symbol(var*"_n")))
end

println("read took: ",reading_input_tile_sum / overall_sum * peons_sum / 60/60,"h")
println("xform took: ",(initializing_sum +transforming_sum) / overall_sum * peons_sum / 60/60,"h")
println("write took: ",saving_output_tiles_sum / overall_sum * peons_sum / 60/60,"h")

using Gadfly
x = ["reading input tile", "initializing", "transforming", "saving output tiles", "waiting",
     "copying single", "merging multiple", "clearing multiple", "reading multiple", "max'ing multiple", "deleting multiple", "writing multiple",
     "clearing octree", "downsampling octree", "saving octree"]
y = map(x->replace(x," ","_")*"_sum", x)
y = [@eval $(Symbol(x)) for x in y]
chart = plot(x=x, y=y, Geom.bar, Guide.xlabel(""), Guide.ylabel(""), Guide.title(basename(ARGS[1])),
      color=[fill("leaf",5)...;fill("merge",7)...;fill("octree",3)...],
      Scale.color_discrete_manual("red","green","blue"),
      Guide.ylabel("CPU time (sec)"));
#      Coord.Cartesian(ymin=0.0,ymax=4e5));
draw(PNG(joinpath(ARGS[1],"beancounter.png"), 6inch, 6inch), chart)
