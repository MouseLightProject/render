# spawned by squatter
# concurrently spawns local peons for each input tile within the sub bounding box
# merges output tiles in memory and local_scratch, and then copies to shared_scratch
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
#  num_procs = min(15,ngpus*ifloor(gpu_ram/tile_ram))  # >4 hits swap
if ngpus == 7
  num_procs = 4
elseif ngpus == 4
  num_procs = 15
else
  nthreads = 8
  num_procs = ifloor(CPU_CORES/nthreads)
end
info(string(CPU_CORES)," CPUs and ",string(ngpus)," GPUs present which can collectively process ",string(num_procs)," tiles simultaneously")

const local_scratch="/scratch/"*readchomp(`whoami`)
const channel=int(ARGS[2])
const manager_bbox = AABBMake(3)  # process all input tiles whose origins are within this bbox
AABBSet(manager_bbox, 3, int(ARGS[3:5]), int(ARGS[6:8]))
const tiles = TileBaseOpen(source)

for i=0:ngpus-1
  cudaSetDevice(i)
  cudaDeviceReset()
end

# delete /dev/shm and local_scratch
t0=time()
rmcontents("/dev/shm", "after")
scratch0 = rmcontents(local_scratch, "after")
info("deleting /dev/shm and local_scratch = ",local_scratch," at start took ",string(iround(time()-t0))," sec")

# read in the transform parameters
using YAML
const meta = YAML.load_file(source*"/tilebase.cache.yml")["tiles"]
const transform = [reshape(meta[i]["transform"],3,8) for i=1:length(meta)]

# get input tiles assigned to this manager
in_tiles_idx = Int[]
in_tiles_aabb = Any[]
manager_aabb = C_NULL  # unioned bbox of assigned input tiles
for i = 1:TileBaseCount(tiles)
  global in_tiles_aabb, manager_aabb
  if AABBHit(TileAABB(TileBaseIndex(tiles, i)), manager_bbox)==1
    if all(AABBGetJ(TileAABB(TileBaseIndex(tiles, i)))[2] .>= AABBGetJ(manager_bbox)[2])
      push!(in_tiles_idx, i)
      tile = TileBaseIndex(tiles, i)
      push!(in_tiles_aabb, AABBCopy(C_NULL, TileAABB(tile)))
      #TileFree(tile)  -> causes TileBaseAABB(tiles) below to segfault
      manager_aabb = AABBUnionIP(manager_aabb, in_tiles_aabb[end])
    end
  end
end

# order tiles to preserve locality, and
# calculate number of input tiles for each output tile
out_tile_path=Int[]

function depth_first_traverse(bbox)
  AABBHit(bbox, manager_aabb)==1 || return
  tmp = map((x)->AABBHit(bbox, x), in_tiles_aabb)
  merge_count[join(out_tile_path, Base.path_separator)] = Uint16[sum(tmp), 0, 0]
  if isleaf(bbox)
    push!(locality_idx, setdiff(find(tmp), locality_idx)...)
  else
    cboxes = AABBBinarySubdivision(bbox)
    for i=1:8
      push!(out_tile_path,i)
      depth_first_traverse(cboxes[i])
      AABBFree(cboxes[i])
      pop!(out_tile_path)
    end
  end
end

const total_ram = int(split(readchomp(`cat /proc/meminfo` |> `head -1`))[2])*1024
ncache = ifloor((total_ram - reserve_ram)/2/prod(shape_leaf_px))   # reserve 32GB for system, scripts, etc.
merge_array = Array(Uint16, shape_leaf_px..., ncache)
merge_used = falses(ncache)
# one entry for each output tile
# [total # input tiles, input tiles processed so far, index to merge_array (0=not assigned yet, Inf=use local_scratch)]
merge_count = Dict{ASCIIString,Array{Uint16,1}}()
info("allocated RAM for ",string(ncache)," output tiles")

locality_idx = Int[]
depth_first_traverse(TileBaseAABB(tiles))
AABBFree(manager_bbox)
AABBFree(manager_aabb)
map(AABBFree, in_tiles_aabb)
TileBaseClose(tiles)

info("assigned ",string(length(in_tiles_idx))," input tiles")
length(in_tiles_idx)==0 && quit()

# keep boss informed
try
  global sock = connect(ARGS[9],int(ARGS[10]))
  println(sock,"manager ",proc_num," is starting job ",join(ARGS[[3 4 5 2]],".")," on ",readchomp(`hostname`),
        " for ",length(in_tiles_idx)," input tiles")
end

@sync begin
  # initialize tcp communication with peons
  # as soon as all output tiles for a given node in the octree have been processed,
  #   concurrently merge and save them to shared_scratch
  hostname2 = readchomp(`hostname`)
  port2 = int(ARGS[10])+1
  global sock2 = Any[]
  server2 = listen(port2)

  ready = r"(peon for input tile )([0-9]*)( has output tile )([1-8/]*)( ready)"
  wrote = r"(peon for input tile )([0-9]*)( wrote output tile )([1-8/]*)( to )"
  sent = r"(peon for input tile )([0-9]*)( will send output tile )([1-8/]*)"
  finished = r"(?<=peon for input tile )[0-9]*(?= is finished)"

  @async merge_output_tiles(() -> while length(sock2)<length(in_tiles_idx)
    push!(sock2, accept(server2))
    @async let sock2=sock2[end]
      while isopen(sock2) || nb_available(sock2)>0
        tmp = chomp(readline(sock2))
        length(tmp)==0 && continue
        println("MANAGER<PEON: ",tmp)
        if ismatch(ready,tmp)
          in_tile_num, out_tile_path = match(ready,tmp).captures[[2,4]]
          if merge_count[out_tile_path][1]>1 && merge_count[out_tile_path][3]==0
            idx = findfirst(merge_used,false)
            if idx!=0
              merge_used[idx] = true
              merge_count[out_tile_path][3] = idx
              info("using RAM slot ",string(idx)," for output tile ",out_tile_path)
            else
              merge_count[out_tile_path][3] = 0xffff
            end
          end
          if merge_count[out_tile_path][3]==0xffff
            msg = "manager tells peon for input tile $in_tile_num to write output tile $out_tile_path to scratch"
          else
            msg = "manager tells peon for input tile $in_tile_num to send output tile $out_tile_path via tcp"
          end
          println("MANAGER>PEON: ",msg)
          println(sock2, msg)
        elseif ismatch(wrote,tmp)
          out_tile_path = match(wrote,tmp).captures[4]
          merge_count[out_tile_path][2]+=1
          if merge_count[out_tile_path][1] == merge_count[out_tile_path][2]
            info("saving output tile ",out_tile_path," from local_scratch to shared_scratch")
            merge_across_filesystems(local_scratch, shared_scratch, join(ARGS[3:5],"-"), "."*string(channel-1)*".tif", out_tile_path, false, true)
          end
        elseif ismatch(sent,tmp)
          global time_max_files, time_ram_file
          out_tile = deserialize(sock2)
          out_tile_path = match(sent,tmp).captures[4]
          merge_count[out_tile_path][2]+=1
          if merge_count[out_tile_path][1]==1
            t0=time()
            info("transferring output tile ",out_tile_path," from RAM to shared_scratch")
            save_out_tile(shared_scratch, out_tile_path, join(ARGS[3:5],"-")*".$(channel-1).tif", out_tile) ||
                  error("shared_scratch is full")
            time_ram_file+=(time()-t0)
          else
            t0=time()
            merge_array[:,:,:,merge_count[out_tile_path][3]] = merge_count[out_tile_path][2]==1 ? out_tile :
                  max(out_tile, merge_array[:,:,:,merge_count[out_tile_path][3]])
            time_max_files+=(time()-t0)
            if merge_count[out_tile_path][1] == merge_count[out_tile_path][2]
              t0=time()
              info("transferring output tile ",out_tile_path," from RAM to shared_scratch")
              save_out_tile(shared_scratch, out_tile_path, join(ARGS[3:5],"-")*".$(channel-1).tif",
                    merge_array[:,:,:,merge_count[out_tile_path][3]]) || error("shared_scratch is full")
              merge_used[merge_count[out_tile_path][3]] = false
              time_ram_file+=(time()-t0)
            end
          end
        elseif ismatch(finished,tmp)
          break
        end
      end
    end
  end )

  # dispatch input tiles to peons
  t0=time()
  i = 1
  nextidx() = (global i; idx=i; i+=1; idx)
  for p = 1:num_procs
    @async begin
      while true
        tile_idx = nextidx()
        tile_idx>length(in_tiles_idx) && break
        cmd = `$(ENV["RENDER_PATH"])$(envpath)/bin/julia $(ENV["RENDER_PATH"])/src/render/peon.jl $(ARGS[1]) $(ngpus>0 ? (p-1) % ngpus : NaN)
              $channel $(in_tiles_idx[locality_idx[tile_idx]]) $(transform[in_tiles_idx[locality_idx[tile_idx]]])
              $(join(ARGS[3:5],"-")) $hostname2 $port2`
        info(string(cmd))
        try
          run(cmd)
        catch
          warn("input tile $(in_tiles_idx[locality_idx[tile_idx]]) might have failed")
        end
      end
    end
  end
end
info("peons took ",string(iround(time()-t0))," sec")
for x in merge_count;  println(x);  end

# delete local_scratch
t0=time()
scratch1 = rmcontents(local_scratch, "before")
info("deleting local_scratch = ",local_scratch," at end took ",string(iround(time()-t0))," sec")

# keep boss informed
try
  println(sock,"manager ",proc_num," has finished job ",join(ARGS[[3 4 5 2]],".")," on ",readchomp(`hostname`),
        " using ",signif((scratch0-scratch1)/1024/1024,4,2)," GB of local_scratch")
  close(sock)
end

info(readchomp(`date`))
