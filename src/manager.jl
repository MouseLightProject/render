# spawned by squatter
# concurrently spawns local peons for each input tile within the sub bounding box
# merges output tiles with more than one input in memory (and local_scratch if needed),
#   otherwise instructs peons to save to shared_scratch
# if used, copies local_scratch to shared_scratch
# saves stdout/err to <destination>/squatter[0-9]*.log

# julia manager.jl parameters.jl originX originY originZ shapeX shapeY shapeZ hostname port

@info string("MANAGER: ",readchomp(`hostname`))
@info string("MANAGER: ",readchomp(`date`))

proc_num = nothing
try;  global proc_num = ENV["LSB_JOBINDEX"];  catch; end

using YAML, Sockets

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

const origin_strs = ARGS[2:4]
const shape_strs = ARGS[5:7]
const hostname_director = ARGS[8]
const port_director = parse(Int,ARGS[9])

# how many peons
ncores = haskey(ENV,"LSB_DJOB_NUMPROC") ? parse(Int,ENV["LSB_DJOB_NUMPROC"]) : Sys.CPU_THREADS
num_procs = leaf_process_oversubscription*div(ncores,leaf_nthreads_per_process)
@info string("MANAGER: ",ncores," CPUs present which can collectively process ",num_procs," tiles simultaneously")

@info string("MANAGER: ","AVX2 = ",has_avx2)

const manager_bbox = AABBMake(3)  # process all input tiles whose origins are within this bbox
AABBSet(manager_bbox, map(x->parse(Int,x),origin_strs), map(x->parse(Int,x),shape_strs))
const tiles = TileBaseOpen(destination)

# delete /dev/shm and local_scratch
t0=time()
rmcontents("/dev/shm", "after", "MANAGER: ")
mkpath(local_scratch)
scratch0 = rmcontents(local_scratch, "after", "MANAGER: ")
@info string("MANAGER: ","deleting /dev/shm and local_scratch = ",local_scratch," at start took ",round(Int,time()-t0)," sec")

# read in the transform parameters
const dims = tiles["tiles"][1]["shape"]["dims"][1:3]
const xlims = tiles["tiles"][1]["grid"]["xlims"]
const ylims = tiles["tiles"][1]["grid"]["ylims"]
const zlims = [x["grid"]["zlims"] for x in tiles["tiles"]]
const transform = [x["grid"]["coordinates"] for x in tiles["tiles"]]
@assert all(diff(diff(xlims)).==0)
@assert all(diff(diff(ylims)).==0)
@assert all(zlim->all(diff(zlim).>0), zlims)
@assert all(diff(map(length,zlims)).==0)
for x in tiles["tiles"]
  @assert xlims == x["grid"]["xlims"]
  @assert ylims == x["grid"]["ylims"]
end

# get input tiles assigned to this manager, and
# precalculate input subtiles' bounding boxes
in_tiles_idx = Int[]
in_subtiles_aabb = Array{Dict,3}[]
manager_aabb = nothing  # unioned bbox of assigned input tiles
for i = 1:TileBaseCount(tiles)
  global in_subtiles_aabb, manager_aabb
  tile = TileBaseIndex(tiles, i)
  tile_aabb = TileAABB(tile)
  if AABBHit(tile_aabb, manager_bbox) &&
        (include_origins_outside_roi || (all(AABBGet(tile_aabb)[1] .>= AABBGet(manager_bbox)[1])))
    push!(in_tiles_idx, i)
    push!(in_subtiles_aabb, calc_in_subtiles_aabb(tile,xlims,ylims,zlims[i],
        reshape(transform[i],3,length(xlims)*length(ylims)*length(zlims[i]))) )
    #TileFree(tile)  -> causes TileBaseAABB(tiles) below to segfault
    manager_aabb = AABBUnion(manager_aabb, tile_aabb)
  end
end

# order input tiles to preserve locality, and
# calculate number of input tiles for each output tile
function depth_first_traverse(bbox,out_tile_path)
  AABBHit(bbox, manager_aabb) || return
  if isleaf(bbox)
    btile = map(in_tile->any(in_subtile->AABBHit(bbox,in_subtile),in_tile), in_subtiles_aabb)
    sum(btile)>0 || return
    merge_count[join(out_tile_path, Base.Filesystem.path_separator)] = UInt16[sum(btile), 0, 0, 0]
    @info string("MANAGER: ","output tile ",join(out_tile_path, Base.Filesystem.path_separator),
         " overlaps with input tiles ",join(in_tiles_idx[findall(btile)],", "))
    dtile = setdiff(findall(btile), locality_idx)
    isempty(dtile) || push!(locality_idx, dtile...)
  else
    cboxes = AABBBinarySubdivision(bbox)
    for i=1:8
      depth_first_traverse(cboxes[i], [out_tile_path...,i])
    end
  end
end

const total_ram = parse(Int,split(readchomp(`head -1 /proc/meminfo`))[2])*1024
ram_fraction = haskey(ENV,"LSB_DJOB_NUMPROC") ? ncores/Sys.CPU_THREADS : 1
ncache = (total_ram - num_procs*peon_ram - other_ram) * ram_fraction/2/prod(shape_leaf_px)/nchannels
ncache = max(1, floor(Int,ncache))
const merge_array = Array{UInt16}(undef, shape_leaf_px..., nchannels, ncache)
const merge_used = falses(ncache)
# one entry for each output tile
# [total # input tiles, input tiles processed so far, input tiles sent so far, index to merge_array (0=not assigned yet, Inf=use local_scratch)]
const merge_count = Dict{String,Array{UInt16,1}}()  # expected, write cmd, write ack, RAM slot
@info string("MANAGER: ","allocated RAM for ",ncache," output tiles")

locality_idx = Int[]
depth_first_traverse(TileBaseAABB(tiles),Int[])
solo_out_tiles = setdiff( String[x[2][1]==1 ? x[1] : "" for x in merge_count] ,[""])

isempty(locality_idx) && @warn("coordinates of input subtiles aren't within bounding box")

@info string("MANAGER: ","assigned ",length(in_tiles_idx)," input tiles")
length(in_tiles_idx)==0 && quit()

# keep boss informed
try
  global sock_director = connect(hostname_director,port_director)
  println(sock_director,"manager ",proc_num," is starting job ",join(origin_strs,'.'),
        " on ",readchomp(`hostname`), " for ",length(in_tiles_idx)," input tiles")
catch
end

const ready_msg = r"(peon for input tile )([0-9]*)( has output tile )([1-8/]*)( ready)"
const wrote_msg = r"(peon for input tile )([0-9]*)( wrote output tile )([1-8/]*)( to )"
const sent_msg = r"(peon for input tile )([0-9]*)( will send output tile )([1-8/]*)"
const saved_msg = r"(peon for input tile )([0-9]*)( saved output tile )([1-8/]*)"
const finished_msg = r"(?<=peon for input tile )[0-9]*(?= is finished)"

function wrangle_peon(sock)
  while !eof(sock)
    msg_from_peon = readline(sock)
    length(msg_from_peon)==0 && continue
    @info string("MANAGER<PEON: ",msg_from_peon)
    local in_tile_num::AbstractString, out_tile_path::AbstractString, out_tile::Array{UInt16,4}
    if occursin(ready_msg, msg_from_peon)
      in_tile_num, out_tile_path = match(ready_msg,msg_from_peon).captures[[2,4]]
      merge_count[out_tile_path][2]+=1
      if merge_count[out_tile_path][4]==0
        idx = findfirst(merge_used.==false)
        if idx!=nothing
          merge_used[idx] = true
          merge_count[out_tile_path][4] = idx
          @info string("MANAGER: ","using RAM slot ",idx," for output tile ",out_tile_path)
        else
          merge_count[out_tile_path][4] = 0xffff
        end
      end
      if merge_count[out_tile_path][4]==0xffff
        if merge_count[out_tile_path][2] < merge_count[out_tile_path][1]
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to write output tile ",out_tile_path," to local_scratch")
          println(sock, msg)
          @info string("MANAGER>PEON: ",msg)
        else
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to merge output tile ",out_tile_path," to shared_scratch")
          println(sock, msg)
          @info string("MANAGER>PEON: ",msg)
        end
      else
        if merge_count[out_tile_path][2] < merge_count[out_tile_path][1]
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to send output tile ",out_tile_path," via tcp")
          println(sock, msg)
          @info string("MANAGER>PEON: ",msg)
        else
          while merge_count[out_tile_path][3] < merge_count[out_tile_path][1]-1;  yield();  end
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to receive output tile ",out_tile_path," via tcp")
          println(sock, msg)
          serialize(sock, merge_array[:,:,:,:,merge_count[out_tile_path][4]])
          @info string("MANAGER>PEON: ",msg)
        end
      end
    elseif occursin(wrote_msg, msg_from_peon)
      out_tile_path = match(wrote_msg,msg_from_peon).captures[4]
      merge_count[out_tile_path][3]+=1
    elseif occursin(sent_msg, msg_from_peon)
      out_tile_path = match(sent_msg,msg_from_peon).captures[4]
      out_tile = deserialize(sock)
      merge_count[out_tile_path][3]+=1
      t1=time()
      ram_slot = merge_count[out_tile_path][4]
      if merge_count[out_tile_path][3]==1
        @inbounds merge_array[:,:,:,:,ram_slot] = out_tile
      else
        for i4=1:nchannels, i3=1:shape_leaf_px[3], i2=1:shape_leaf_px[2], i1=1:shape_leaf_px[1]
          @inbounds merge_array[i1,i2,i3,i4,ram_slot] =
                max(out_tile[i1,i2,i3,i4], merge_array[i1,i2,i3,i4,ram_slot])
        end
      end
      time_max_files=time()-t1
      @info string("MANAGER: ","max'ing multiple files took ",round(time_max_files, sigdigits=4)," sec")
    elseif occursin(saved_msg, msg_from_peon)
      out_tile_path = match(saved_msg,msg_from_peon).captures[4]
      merge_used[merge_count[out_tile_path][4]] = false
    elseif occursin(finished_msg, msg_from_peon)
      break
    end
  end
  out_tile = Array{UInt16}(undef, 0,0,0,0)
  GC.gc()
end

t0=time()
@sync begin
  # initialize tcp communication with peons
  # as soon as all output tiles for a given leaf in the octree have been processed,
  #   concurrently merge and save them to shared_scratch
  hostname_manager = readchomp(`hostname`)
  default_port_manager = port_director+1
  global ntiles_processed=0
  server_manager, port_manager = get_available_port(default_port_manager)

  @async while ntiles_processed<length(in_tiles_idx)
    sock_peon = accept(server_manager)
    global ntiles_processed
    ntiles_processed+=1
    @async let sock_peon=sock_peon
      wrangle_peon(sock_peon)
    end
  end

  # dispatch input tiles to peons
  global i = 1
  nextidx() = (global i; idx=i; i+=1; idx)
  for p = 1:num_procs
    @async while true
      tile_idx = nextidx()
      tile_idx>length(locality_idx) && break
      cmd = `$(ENV["JULIA"]) $(ENV["RENDER_PATH"])/src/render/src/peon.jl $(ARGS[1])
            $(in_tiles_idx[locality_idx[tile_idx]]) $(join(origin_strs,"-")) $(string(solo_out_tiles))
            $hostname_manager $port_manager $(length(xlims)) $xlims $(length(ylims)) $ylims
            $(length(zlims[in_tiles_idx[locality_idx[tile_idx]]]))
            $(zlims[in_tiles_idx[locality_idx[tile_idx]]])
            $(dims)
            $(transform[in_tiles_idx[locality_idx[tile_idx]]])`
      @info string("MANAGER: ",cmd)
      try
        run(cmd)
      catch e
        @warn string("peon for input tile ",in_tiles_idx[locality_idx[tile_idx]]," might have failed: ",e)
      end
    end
  end
end
@info string("MANAGER: ","peons took ",round(Int,time()-t0)," sec")

for (k,v) in merge_count
  @info string("MANAGER: ",(k,v))
  v[1]>1 && v[1]!=v[2] && @warn string("not all input tiles processed for output tile ",k," : ",v)
end

# delete local_scratch
t0=time()
scratch1 = rmcontents(local_scratch, "before", "MANAGER: ")
@info string("MANAGER: ","deleting local_scratch = ",local_scratch," at end took ",round(Int,time()-t0)," sec")

#closelibs()

# keep boss informed
try
  println(sock_director,"manager ",proc_num," has finished job ",join(origin_strs,'.')," on ",
        readchomp(`hostname`), " using ",round((scratch0-scratch1)/1024/1024, sigdigits=4)," GB of local_scratch")
  close(sock_director)
catch
end

@info string("MANAGER: ",readchomp(`date`))
