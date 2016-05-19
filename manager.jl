# spawned by squatter
# concurrently spawns local peons for each input tile within the sub bounding box
# merges output tiles with more than one input in memory (and local_scratch if needed),
#   otherwise instructs peons to save to shared_scratch
# if used, copies local_scratch to shared_scratch
# saves stdout/err to <destination>/[0-9]*.log

# julia manager.jl parameters.jl channel originX originY originZ shapeX shapeY shapeZ hostname port

const reserve_ram = 32e9  # how much RAM to *not* use for output tile scratch space
const tile_ram = 0.85e9  # generalize

info(readchomp(`hostname`))
info(readchomp(`date`))

proc_num = nothing
try;  global proc_num = ENV["SGE_TASK_ID"];  end

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(ENV["RENDER_PATH"]*"/src/render/admin.jl")

# how many peons
#if ngpus>0
#  gpu_ram = cudaMemGetInfo()[2]
#  num_procs = min(15,ngpus*floor(Int,gpu_ram/tile_ram))  # >4 hits swap
if ngpus == 7
  num_procs = 7
elseif ngpus == 4
  num_procs = 15
else
  nthreads = 8  # must match barycentricCPU.c
  num_procs = floor(Int,CPU_CORES/nthreads)
end
info(string(CPU_CORES)," CPUs and ",string(ngpus)," GPUs present which can collectively process ",string(num_procs)," tiles simultaneously")

const local_scratch="/scratch/"*readchomp(`whoami`)
const channel=parse(Int,ARGS[2])
const manager_bbox = AABBMake(3)  # process all input tiles whose origins are within this bbox
AABBSet(manager_bbox, 3, map(x->parse(Int,x),ARGS[3:5]), map(x->parse(Int,x),ARGS[6:8]))
const tiles = TileBaseOpen(source)

for i=0:ngpus-1
  cudaSetDevice(i)
  cudaDeviceReset()
end

# delete /dev/shm and local_scratch
t0=time()
rmcontents("/dev/shm", "after")
scratch0 = rmcontents(local_scratch, "after")
info("deleting /dev/shm and local_scratch = ",local_scratch," at start took ",string(round(Int,time()-t0))," sec")

# read in the transform parameters
using YAML
const meta = YAML.load(replace(readall(source*"/tilebase.cache.yml"),['[',',',']'],""))
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
    merge_count[join(out_tile_path, Base.path_separator)] = UInt16[sum(btile), 0, 0, 0]
    info("output tile ",join(out_tile_path, Base.path_separator),
         " overlaps with input tiles ",join(in_tiles_idx[find(btile)],", "))
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

const total_ram = parse(Int,split(readchomp(pipeline(`cat /proc/meminfo`,`head -1`)))[2])*1024
ncache = floor(Int,(total_ram - reserve_ram)/2/prod(shape_leaf_px))   # reserve some RAM for system, scripts, etc.
merge_array = Array(UInt16, shape_leaf_px..., ncache)
merge_used = falses(ncache)
# one entry for each output tile
# [total # input tiles, input tiles processed so far, input tiles sent so far, index to merge_array (0=not assigned yet, Inf=use local_scratch)]
merge_count = Dict{ASCIIString,Array{UInt16,1}}()  # expected, write cmd, write ack, RAM slot
info("allocated RAM for ",string(ncache)," output tiles")

locality_idx = Int[]
depth_first_traverse(TileBaseAABB(tiles),Int[])
solo_out_tiles = setdiff( ASCIIString[x[2][1]==1 ? x[1] : "" for x in merge_count] ,[""])
AABBFree(manager_bbox)
AABBFree(manager_aabb)
map(x->map(AABBFree,x), in_subtiles_aabb)
TileBaseClose(tiles)

info("assigned ",string(length(in_tiles_idx))," input tiles")
length(in_tiles_idx)==0 && quit()

# keep boss informed
try
  global sock = connect(ARGS[9],parse(Int,ARGS[10]))
  println(sock,"manager ",proc_num," is starting job ",join(ARGS[[3 4 5 2]],".")," on ",readchomp(`hostname`),
        " for ",length(in_tiles_idx)," input tiles")
end

t0=time()
@sync begin
  # initialize tcp communication with peons
  # as soon as all output tiles for a given leaf in the octree have been processed,
  #   concurrently merge and save them to shared_scratch
  hostname2 = readchomp(`hostname`)
  port2 = parse(Int,ARGS[10])+1
  global sock2 = Any[]
  server2 = listen(port2)

  const ready = r"(peon for input tile )([0-9]*)( has output tile )([1-8/]*)( ready)"
  const wrote = r"(peon for input tile )([0-9]*)( wrote output tile )([1-8/]*)( to )"
  const sent = r"(peon for input tile )([0-9]*)( will send output tile )([1-8/]*)"
  const saved = r"(peon for input tile )([0-9]*)( saved output tile )([1-8/]*)"
  const finished = r"(?<=peon for input tile )[0-9]*(?= is finished)"

  @async merge_output_tiles(() -> while length(sock2)<length(in_tiles_idx)
    push!(sock2, accept(server2))
    @async let sock2=sock2[end]
      while isopen(sock2) || nb_available(sock2)>0
        tmp = chomp(readline(sock2))
        length(tmp)==0 && continue
        println(STDERR,"MANAGER<PEON: ",tmp)
        local in_tile_num, out_tile_path
        if ismatch(ready,tmp)
          in_tile_num, out_tile_path = match(ready,tmp).captures[[2,4]]
          merge_count[out_tile_path][2]+=1
          if merge_count[out_tile_path][4]==0
            idx = findfirst(merge_used,false)
            if idx!=0
              merge_used[idx] = true
              merge_count[out_tile_path][4] = idx
              info("using RAM slot ",string(idx)," for output tile ",out_tile_path)
            else
              merge_count[out_tile_path][4] = 0xffff
            end
          end
          if merge_count[out_tile_path][4]==0xffff
            msg = "manager tells peon for input tile $in_tile_num to write output tile $out_tile_path to local_scratch"
            println(sock2, msg)
            println(STDERR,"MANAGER>PEON: ",msg)
          elseif merge_count[out_tile_path][2] < merge_count[out_tile_path][1]
            msg = "manager tells peon for input tile $in_tile_num to send output tile $out_tile_path via tcp"
            println(sock2, msg)
            println(STDERR,"MANAGER>PEON: ",msg)
          else
            while merge_count[out_tile_path][3] < merge_count[out_tile_path][1]-1;  yield();  end
            msg = "manager tells peon for input tile $in_tile_num to receive output tile $out_tile_path via tcp"
            println(sock2, msg)
            serialize(sock2, merge_array[:,:,:,merge_count[out_tile_path][4]])
            println(STDERR,"MANAGER>PEON: ",msg)
          end
        elseif ismatch(wrote,tmp)
          out_tile_path = match(wrote,tmp).captures[4]
          merge_count[out_tile_path][3]+=1
          if merge_count[out_tile_path][1] == merge_count[out_tile_path][3]
            merge_across_filesystems(local_scratch, shared_scratch, join(ARGS[3:5],"-"), "."*string(channel-1)*".tif", out_tile_path, false, false, true)
            info("saved output tile ",out_tile_path," from local_scratch to shared_scratch")
          end
        elseif ismatch(sent,tmp)
          global time_max_files
          out_tile_path = match(sent,tmp).captures[4]
          out_tile::Array{UInt16,3} = deserialize(sock2)
          merge_count[out_tile_path][3]+=1
          t1=time()
          merge_array[:,:,:,merge_count[out_tile_path][4]] = merge_count[out_tile_path][3]==1 ? out_tile :
                max(out_tile, merge_array[:,:,:,merge_count[out_tile_path][4]]::Array{UInt16,3})
          time_max_files+=(time()-t1)
        elseif ismatch(saved,tmp)
          out_tile_path = match(saved,tmp).captures[4]
          merge_used[merge_count[out_tile_path][4]] = false
        elseif ismatch(finished,tmp)
          break
        end
      end
    end
  end )

  # dispatch input tiles to peons
  i = 1
  nextidx() = (global i; idx=i; i+=1; idx)
  for p = 1:num_procs
    @async begin
      while true
        tile_idx = nextidx()
        tile_idx>length(in_tiles_idx) && break
        cmd = `$(ENV["JULIA"]) $(ENV["RENDER_PATH"])/src/render/peon.jl $(ARGS[1]) $(ngpus>0 ? (p-1) % ngpus : NaN)
              $channel $(in_tiles_idx[locality_idx[tile_idx]]) $(join(ARGS[3:5],"-")) $(string(solo_out_tiles))
              $hostname2 $port2 $(length(xlims)) $xlims $(length(ylims)) $ylims
              $(length(zlims[in_tiles_idx[locality_idx[tile_idx]]]))
              $(zlims[in_tiles_idx[locality_idx[tile_idx]]])
              $(dims[in_tiles_idx[locality_idx[tile_idx]]])
              $(transform[in_tiles_idx[locality_idx[tile_idx]]])`
        info(string(cmd))
        try
          run(cmd)
        catch
          warn("peon for input tile $(in_tiles_idx[locality_idx[tile_idx]]) might have failed")
        end
      end
    end
  end
end
info("peons took ",string(round(Int,time()-t0))," sec")

for (k,v) in merge_count
  info(string((k,v)))
  v[1]>1 && v[1]!=v[2] && warn("not all input tiles processed for output tile ",string(k)," : ",string(v))
end

# delete local_scratch
t0=time()
scratch1 = rmcontents(local_scratch, "before")
info("deleting local_scratch = ",local_scratch," at end took ",string(round(Int,time()-t0))," sec")

closelibs()

# keep boss informed
try
  println(sock,"manager ",proc_num," has finished job ",join(ARGS[[3 4 5 2]],".")," on ",readchomp(`hostname`),
        " using ",signif((scratch0-scratch1)/1024/1024,4,2)," GB of local_scratch")
  close(sock)
end

info(readchomp(`date`))
