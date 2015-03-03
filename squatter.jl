# qsub'ed by director
# sequentially spawns a local manager for each sub-bounding box, and
# handle one thread of inter-node merge by copying shared_scratch to destination
# saves stdout/err to <destination>/[0-9]*.log

# julia squatter.jl parameters.jl hostname port

include(ARGS[1])
include(ENV["RENDER_PATH"]*"/src/render/admin.jl")

const proc_num = ENV["SGE_TASK_ID"]

const dole_out = Regex("squatter "*proc_num*" dole out job")
const merge = Regex("squatter "*proc_num*" merge")
const terminate = Regex("squatter "*proc_num*" terminate")

split(readchomp(`hostname`),".")[1] in bad_nodes && exit(1)

# keep boss informed
sock = connect(ARGS[2],int(ARGS[3]))
println(sock,"squatter ",proc_num," is ready on ",readchomp(`hostname`))

function doit(cmd)
  info(string(cmd))
  try
    run(cmd)
  catch
    warn("manager $proc_num might have failed")
  end
  msg = "squatter $proc_num is finished"
  println("SQUATTER>DIRECTOR: ",msg)
  println(sock,msg)
end

while isopen(sock) || nb_available(sock)>0
  tmp = chomp(readline(sock))
  length(tmp)==0 && continue
  println("SQUATTER<DIRECTOR: ",tmp)
  if ismatch(dole_out,tmp)
    doit(`$(ENV["RENDER_PATH"])$(envpath)/bin/julia $(ENV["RENDER_PATH"])/src/render/manager.jl $(split(tmp)[6:end])`)
  elseif ismatch(merge,tmp)
    doit(`$(ENV["RENDER_PATH"])$(envpath)/bin/julia -L $(ENV["RENDER_PATH"])/src/render/admin.jl -L $destination/calculated_parameters.jl -e $(join(split(tmp)[4:end]," "))`)
  elseif ismatch(terminate,tmp)
    msg = "squatter $proc_num is terminating"
    println("SQUATTER>DIRECTOR: ",msg)
    println(sock,msg)
    close(sock)
    quit()
  end
end
