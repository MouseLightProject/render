# spawned by squatter
# concurrently spawns local peons for each input tile within the sub bounding box
# merges output tiles with more than one input in memory (and local_scratch if needed),
#   otherwise instructs peons to save to shared_scratch
# if used, copies local_scratch to shared_scratch
# saves stdout/err to <destination>/squatter[0-9]*.log

# julia manager.jl parameters.jl originX originY originZ shapeX shapeY shapeZ hostname port

info(readchomp(`hostname`), prefix="MANAGER: ")
info(readchomp(`date`), prefix="MANAGER: ")

proc_num = nothing
try;  global proc_num = ENV["LSB_JOBINDEX"];  end

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(ENV["RENDER_PATH"]*"/src/render/src/admin.jl")

const origin_strs = ARGS[2:4]
const shape_strs = ARGS[5:7]
const hostname_director = ARGS[8]
const port_director = parse(Int,ARGS[9])

# how many peons
nthreads = 8  # should match barycentricCPU.c
ncores = haskey(ENV,"LSB_DJOB_NUMPROC") ? parse(Int,ENV["LSB_DJOB_NUMPROC"]) : Sys.CPU_CORES
num_procs = div(ncores,nthreads)
info(ncores," CPUs present which can collectively process ",num_procs," tiles simultaneously", prefix="MANAGER: ")

info("AVX2 = ",has_avx2, prefix="MANAGER: ")

const local_scratch="/scratch/"*readchomp(`whoami`)
const manager_bbox = AABBMake(3)  # process all input tiles whose origins are within this bbox
AABBSet(manager_bbox, 3, map(x->parse(Int,x),origin_strs), map(x->parse(Int,x),shape_strs))
const tiles = TileBaseOpen(source)

# delete /dev/shm and local_scratch
t0=time()
rmcontents("/dev/shm", "after", "MANAGER: ")
scratch0 = rmcontents(local_scratch, "after", "MANAGER: ")
info("deleting /dev/shm and local_scratch = ",local_scratch," at start took ",round(Int,time()-t0)," sec", prefix="MANAGER: ")

# read in the transform parameters
using YAML
const meta = YAML.load(replace(readstring(source*"/tilebase.cache.yml"),['[',',',']'],""))
const dims = [map(x->parse(Int,x), split(x["shape"]["dims"]))[1:3] for x in meta["tiles"]]
const xlims = map(x->parse(Int,x), split(meta["tiles"][1]["grid"]["xlims"]))
const ylims = map(x->parse(Int,x), split(meta["tiles"][1]["grid"]["ylims"]))
const zlims = [map(x->parse(Int,x), split(x["grid"]["zlims"])) for x in meta["tiles"]]
const transform = [map(x->parse(Int,x), split(x["grid"]["coordinates"])) for x in meta["tiles"]]
@assert all(diff(diff(xlims)).==0)
@assert all(diff(diff(ylims)).==0)
@assert all(zlim->all(diff(zlim).>0), zlims)
@assert all(diff(map(length,zlims)).==0)
for x in meta["tiles"]
  @assert xlims == map(x->parse(Int,x), split(x["grid"]["xlims"]))
  @assert ylims == map(x->parse(Int,x), split(x["grid"]["ylims"]))
end

# get input tiles assigned to this manager, and
# precalculate input subtiles' bounding boxes
in_tiles_idx = Int[]
in_subtiles_aabb = Array{Ptr{Void},3}[]
manager_aabb = C_NULL  # unioned bbox of assigned input tiles
for i = 1:TileBaseCount(tiles)
  global in_subtiles_aabb, manager_aabb
  tile = TileBaseIndex(tiles, i)
  tile_aabb = TileAABB(tile)
  if AABBHit(tile_aabb, manager_bbox) &&
        (include_origins_outside_roi || (all(AABBGetJ(tile_aabb)[2] .>= AABBGetJ(manager_bbox)[2])))
    push!(in_tiles_idx, i)
    push!(in_subtiles_aabb, calc_in_subtiles_aabb(tile,xlims,ylims,zlims[i],
        reshape(transform[i],3,length(xlims)*length(ylims)*length(zlims[i]))) )
    #TileFree(tile)  -> causes TileBaseAABB(tiles) below to segfault
    manager_aabb = AABBUnionIP(manager_aabb, AABBCopy(C_NULL, tile_aabb))
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
    info("output tile ",join(out_tile_path, Base.Filesystem.path_separator),
         " overlaps with input tiles ",join(in_tiles_idx[find(btile)],", "), prefix="MANAGER: ")
    dtile = setdiff(find(btile), locality_idx)
    isempty(dtile) || push!(locality_idx, dtile...)
  else
    cboxes = AABBBinarySubdivision(bbox)
    for i=1:8
      depth_first_traverse(cboxes[i], [out_tile_path...,i])
      AABBFree(cboxes[i])
    end
  end
end

const total_ram = parse(Int,split(readchomp(`head -1 /proc/meminfo`))[2])*1024
ram_fraction = haskey(ENV,"LSB_DJOB_NUMPROC") ? ncores/Sys.CPU_CORES : 1
ncache = (total_ram - num_procs*peon_ram - other_ram) * ram_fraction/2/prod(shape_leaf_px)/nchannels
ncache = max(1, floor(Int,ncache))
const merge_array = Array{UInt16}(shape_leaf_px..., nchannels, ncache)
const merge_used = falses(ncache)
# one entry for each output tile
# [total # input tiles, input tiles processed so far, input tiles sent so far, index to merge_array (0=not assigned yet, Inf=use local_scratch)]
const merge_count = Dict{String,Array{UInt16,1}}()  # expected, write cmd, write ack, RAM slot
info("allocated RAM for ",ncache," output tiles", prefix="MANAGER: ")

locality_idx = Int[]
depth_first_traverse(TileBaseAABB(tiles),Int[])
solo_out_tiles = setdiff( String[x[2][1]==1 ? x[1] : "" for x in merge_count] ,[""])
AABBFree(manager_bbox)
AABBFree(manager_aabb)
map(x->map(AABBFree,x), in_subtiles_aabb)
TileBaseClose(tiles)

isempty(locality_idx) && warn("coordinates of input subtiles aren't within bounding box")

info("assigned ",length(in_tiles_idx)," input tiles", prefix="MANAGER: ")
length(in_tiles_idx)==0 && quit()

# keep boss informed
try
  global sock_director = connect(hostname_director,port_director)
  println(sock_director,"manager ",proc_num," is starting job ",join(origin_strs,'.'),
        " on ",readchomp(`hostname`), " for ",length(in_tiles_idx)," input tiles")
end

const ready_msg = r"(peon for input tile )([0-9]*)( has output tile )([1-8/]*)( ready)"
const wrote_msg = r"(peon for input tile )([0-9]*)( wrote output tile )([1-8/]*)( to )"
const sent_msg = r"(peon for input tile )([0-9]*)( will send output tile )([1-8/]*)"
const saved_msg = r"(peon for input tile )([0-9]*)( saved output tile )([1-8/]*)"
const finished_msg = r"(?<=peon for input tile )[0-9]*(?= is finished)"

function wrangle_peon(sock)
  while isopen(sock) || nb_available(sock)>0
    msg_from_peon = chomp(readline(sock,chomp=false))
    length(msg_from_peon)==0 && continue
    info(msg_from_peon, prefix="MANAGER<PEON: ")
    local in_tile_num::AbstractString, out_tile_path::AbstractString, out_tile::Array{UInt16,4}
    if ismatch(ready_msg, msg_from_peon)
      in_tile_num, out_tile_path = match(ready_msg,msg_from_peon).captures[[2,4]]
      merge_count[out_tile_path][2]+=1
      if merge_count[out_tile_path][4]==0
        idx = findfirst(merge_used,false)
        if idx!=0
          merge_used[idx] = true
          merge_count[out_tile_path][4] = idx
          info("using RAM slot ",idx," for output tile ",out_tile_path, prefix="MANAGER: ")
        else
          merge_count[out_tile_path][4] = 0xffff
        end
      end
      if merge_count[out_tile_path][4]==0xffff
        if merge_count[out_tile_path][2] < merge_count[out_tile_path][1]
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to write output tile ",out_tile_path," to local_scratch")
          println(sock, msg)
          info(msg, prefix="MANAGER>PEON: ")
        else
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to merge output tile ",out_tile_path," to shared_scratch")
          println(sock, msg)
          info(msg, prefix="MANAGER>PEON: ")
        end
      else
        if merge_count[out_tile_path][2] < merge_count[out_tile_path][1]
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to send output tile ",out_tile_path," via tcp")
          println(sock, msg)
          info(msg, prefix="MANAGER>PEON: ")
        else
          while merge_count[out_tile_path][3] < merge_count[out_tile_path][1]-1;  yield();  end
          msg = string("manager tells peon for input tile ",in_tile_num,
                " to receive output tile ",out_tile_path," via tcp")
          println(sock, msg)
          serialize(sock, merge_array[:,:,:,:,merge_count[out_tile_path][4]])
          info(msg, prefix="MANAGER>PEON: ")
        end
      end
    elseif ismatch(wrote_msg, msg_from_peon)
      out_tile_path = match(wrote_msg,msg_from_peon).captures[4]
      merge_count[out_tile_path][3]+=1
    elseif ismatch(sent_msg, msg_from_peon)
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
      info("max'ing multiple files took ",signif(time_max_files,4)," sec", prefix="MANAGER: ")
    elseif ismatch(saved_msg, msg_from_peon)
      out_tile_path = match(saved_msg,msg_from_peon).captures[4]
      merge_used[merge_count[out_tile_path][4]] = false
    elseif ismatch(finished_msg, msg_from_peon)
      break
    end
  end
  out_tile = Array{UInt16}(0,0,0,0)
  gc()
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
  i = 1
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
            $(dims[in_tiles_idx[locality_idx[tile_idx]]])
            $(transform[in_tiles_idx[locality_idx[tile_idx]]])`
      info(cmd, prefix="MANAGER: ")
      try
        run(cmd)
      catch e
        warn("peon for input tile ",in_tiles_idx[locality_idx[tile_idx]]," might have failed: ",e)
      end
    end
  end
end
info("peons took ",round(Int,time()-t0)," sec", prefix="MANAGER: ")

for (k,v) in merge_count
  info((k,v), prefix="MANAGER: ")
  v[1]>1 && v[1]!=v[2] && warn("not all input tiles processed for output tile ",k," : ",v)
end

# delete local_scratch
t0=time()
scratch1 = rmcontents(local_scratch, "before", "MANAGER: ")
info("deleting local_scratch = ",local_scratch," at end took ",round(Int,time()-t0)," sec", prefix="MANAGER: ")

#closelibs()

# keep boss informed
try
  println(sock_director,"manager ",proc_num," has finished job ",join(origin_strs,'.')," on ",
        readchomp(`hostname`), " using ",signif((scratch0-scratch1)/1024/1024,4)," GB of local_scratch")
  close(sock_director)
end

info(readchomp(`date`), prefix="MANAGER: ")
