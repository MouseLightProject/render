# bsub'ed by director
# sequentially spawns a local manager for each sub-bounding box, and
# saves stdout/err to <destination>/squatter[0-9]*.log

# julia squatter.jl parameters.jl hostname port

using Sockets

include(ARGS[1])
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

const proc_num = ENV["LSB_JOBINDEX"]

const dole_out = Regex("squatter "*proc_num*" dole out job")
const terminate = Regex("squatter "*proc_num*" terminate")

split(readchomp(`hostname`),".")[1] in bad_nodes && exit(1)

# keep boss informed
sock = connect(ARGS[2],parse(Int,ARGS[3]))
println(sock,"squatter ",proc_num," is ready on ",readchomp(`hostname`))

while isopen(sock) || bytesavailable(sock)>0
  tmp = chomp(readline(sock,keep=true))
  length(tmp)==0 && continue
  @info string("SQUATTER<DIRECTOR: ",tmp)
  if occursin(dole_out,tmp)
    cmd=`$(ENV["JULIA"]) $(ENV["RENDER_PATH"])/src/render/src/manager.jl $(split(tmp)[6:end])`
    @info string("SQUATTER: ",cmd)
    try
      run(cmd)
    catch e
      @warn string("manager $proc_num might have failed: ",e)
    end
    msg = "squatter $proc_num is finished"
    println(sock,msg)
    @info string("SQUATTER>DIRECTOR: ",msg)
  elseif occursin(terminate,tmp)
    msg = "squatter $proc_num is terminating"
    println(sock,msg)
    @info string("SQUATTER>DIRECTOR: ",msg)
    close(sock)
    exit()
  end
end

#closelibs()
