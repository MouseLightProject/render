# qsub'ed by director
# sequentially spawns a local manager for each sub-bounding box, and
# saves stdout/err to <destination>/[0-9]*.log

# julia squatter.jl parameters.jl hostname port

include(ARGS[1])
include(ENV["RENDER_PATH"]*"/src/render/src/admin.jl")

const proc_num = ENV["SGE_TASK_ID"]

const dole_out = Regex("squatter "*proc_num*" dole out job")
const terminate = Regex("squatter "*proc_num*" terminate")

split(readchomp(`hostname`),".")[1] in bad_nodes && exit(1)

# keep boss informed
sock = connect(ARGS[2],parse(Int,ARGS[3]))
println(sock,"squatter ",proc_num," is ready on ",readchomp(`hostname`))

while isopen(sock) || nb_available(sock)>0
  tmp = chomp(readline(sock))
  length(tmp)==0 && continue
  info(tmp, prefix="SQUATTER<DIRECTOR: ")
  if ismatch(dole_out,tmp)
    cmd=`$(ENV["JULIA"]) $(ENV["RENDER_PATH"])/src/render/src/manager.jl $(split(tmp)[6:end])`
    info(cmd, prefix="SQUATTER: ")
    try
      run(cmd)
    catch
      warn("manager $proc_num might have failed")
    end
    msg = "squatter $proc_num is finished"
    println(sock,msg)
    info(msg, prefix="SQUATTER>DIRECTOR: ")
  elseif ismatch(terminate,tmp)
    msg = "squatter $proc_num is terminating"
    println(sock,msg)
    info(msg, prefix="SQUATTER>DIRECTOR: ")
    close(sock)
    quit()
  end
end

#closelibs()
