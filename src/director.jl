# bsub'ed by render to one core of a regular compute node
# bsubs a bunch of squatters to gpu and/or cpu nodes
# partitions the bounding box of the tilespace into countof_job sized sub bounding boxes
# parcels out multiple sub bounding boxes to each squatter
# saves stdout/err to <destination>/render.log

# julia director.jl parameters.jl jobname

info(readchomp(`date`), prefix="DIRECTOR: ")
info(readchomp(`hostname`), prefix="DIRECTOR: ")

include(ARGS[1])
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

const jobname = ARGS[2]
const tiles = TileBaseOpen(source)
tile_shape = TileShape(TileBaseIndex(tiles,1))
const tile_type = ndtype(tile_shape)
const nchannels = ndshapeJ(tile_shape)[4]

# delete scratch
t0=time()
info("source = ",source, prefix="DIRECTOR: ")
info("destination = ",destination, prefix="DIRECTOR: ")
mkpath(shared_scratch)
scratch0 = rmcontents(shared_scratch, "after", "DIRECTOR: ")
info("deleting shared_scratch = ",shared_scratch," at start took ",round(Int,time()-t0)," sec", prefix="DIRECTOR: ")

# get the max output tile size
tiles_bbox = AABBGetJ(TileBaseAABB(tiles))
const shape_tiles_nm = tiles_bbox[3]
const nlevels = max(0, ceil(Int,
    log(8, prod(map(Float64,shape_tiles_nm)) / (prod(voxelsize_um)*um2nm^3) / max_pixels_per_leaf) ))
shape_leaf_px_initial = round.(Int, round.(shape_tiles_nm./um2nm./voxelsize_um./2^nlevels, -1, 2))
# ensure that the leaf volume is divisible by 32*32*4 (for GPU), and
# that each leaf dimension is divisible by leaf_dim_divisible_by (for chunking)
xyz=Array{Int}(3)
cost=Inf32
const shape_leaf_dim_search_range = -20:2:20
for x=shape_leaf_dim_search_range, y=shape_leaf_dim_search_range, z=shape_leaf_dim_search_range
  if mod(prod(shape_leaf_px_initial+[x,y,z]), 32*32*4)==0 &&
     all(map(x->mod(x,leaf_dim_divisible_by), shape_leaf_px_initial+[x,y,z]).==0) &&
     sum(abs.([x,y,z]))<cost
    xyz=[x,y,z]
    cost=sum(abs.([x,y,z]))
    info("adjusting leaf_shape: cost=",cost," delta_xyz=",xyz, prefix="DIRECTOR: ")
  end
end
cost==Inf32 && error("can't find satisfactory shape_leaf_px")
const shape_leaf_px = shape_leaf_px_initial+xyz
const voxelsize_used_um = shape_tiles_nm./um2nm./2^nlevels ./ shape_leaf_px

git_version(path) = readchomp(`git --git-dir=$(path)/.git log -1 --pretty=format:"%ci %H"`)

# write parameter files to destination
open("$destination/calculated_parameters.jl","w") do f
  println(f,"const jobname = \"",jobname,"\"")
  println(f,"const nlevels = ",nlevels)
  println(f,"const nchannels = ",nchannels)
  println(f,"const shape_leaf_px = [",join(map(string,shape_leaf_px),","),"]")
  println(f,"const voxelsize_used_um = [",
        voxelsize_used_um[1], ',', voxelsize_used_um[2], ',', voxelsize_used_um[3], ']')
  println(f,"const origin_nm = [",join(map(string,tiles_bbox[2]),","),"]")
  println(f,"const tile_type = convert(Cint,$tile_type)")
  for repo in ["render", "mltk-bary", "tilebase", "nd", "ndio-series", "ndio-tiff", "ndio-hdf5", "mylib"]
    println(f,"const $(replace(repo,'-','_'))_version = \"",git_version(joinpath(ENV["RENDER_PATH"],"src",repo)),"\"")
  end
end
open("$destination/transform.txt","w") do f  # for large volume viewer
  println(f,"ox: ",tiles_bbox[2][1])
  println(f,"oy: ",tiles_bbox[2][2])
  println(f,"oz: ",tiles_bbox[2][3])
  println(f,"sx: ",voxelsize_used_um[1]*um2nm*2^nlevels)
  println(f,"sy: ",voxelsize_used_um[2]*um2nm*2^nlevels)
  println(f,"sz: ",voxelsize_used_um[3]*um2nm*2^nlevels)
  println(f,"nl: ",nlevels+1)
end
cp(joinpath(source,"tilebase.cache.yml"), joinpath(destination,"tilebase.cache.yml"))
info("number of levels = ",nlevels, prefix="DIRECTOR: ")
info("shape of output tiles is [",join(map(string,shape_leaf_px),","),"] pixels", prefix="DIRECTOR: ")
info("voxel dimensions used to make output tile shape even and volume divisible by 32*32*4: [",
    join(map(string,voxelsize_used_um),",")," microns", prefix="DIRECTOR: ")

# divide in halves instead of eighths for finer-grained use of RAM and local_scratch
function AABBHalveSubdivision(bbox)
  bbox1 = deepcopy(bbox)
  bbox2 = deepcopy(bbox)
  idx = indmax(bbox[3])
  bbox1[3][idx] = floor(bbox1[3][idx]/2)
  bbox2[3][idx] = ceil(bbox2[3][idx]/2)
  bbox2[2][idx] += bbox1[3][idx]
  bbox1, bbox2
end

function get_job_aabbs(bbox)
  bbox_aabb=AABBSet(C_NULL,3,bbox[2],bbox[3])
  ntiles=0
  for i=1:TileBaseCount(tiles)
    tile_aabb = TileAABB(TileBaseIndex(tiles,i))
    AABBHit(tile_aabb, bbox_aabb) &&
        (include_origins_outside_roi || (all(AABBGetJ(tile_aabb)[2] .>= bbox[2]))) &&
        (ntiles+=1)
  end
  if ntiles > max_tilechannels_per_job / nchannels
    map(get_job_aabbs, AABBHalveSubdivision(bbox))
  elseif ntiles>0
    push!(job_aabbs, (bbox, ntiles))
  end
  AABBFree(bbox_aabb)
end

job_aabbs = []
tiles_bbox[2][:] = round.(Int,tiles_bbox[2][:] + tiles_bbox[3].*region_of_interest[1])
tiles_bbox[3][:] = round.(Int,tiles_bbox[3][:] .* region_of_interest[2])
get_job_aabbs(tiles_bbox)
sort!(job_aabbs; lt=(x,y)->x[2]<y[2], rev=true)
roi_vol = prod(region_of_interest[2])
info(TileBaseCount(tiles),(roi_vol<1 ? "*"*string(roi_vol): ""),
      " input tiles each with ",nchannels," channels split into ",length(job_aabbs)," jobs", prefix="DIRECTOR: ")

include_origins_outside_roi && length(job_aabbs)>1 &&
      warn("include_origins_outside_roi should be true only when there is just one job")

TileBaseClose(tiles)

# initialize tcp communication with squatters
nnodes = min( length(job_aabbs),
              throttle_leaf_nmachines,
              which_cluster=="janelia" ? 96 : length(which_cluster) )
info("number of cluster nodes used = $nnodes", prefix="DIRECTOR: ")
events = Array{Condition}(nnodes,2)
hostname = readchomp(`hostname`)
default_port = 2000
ready = r"(?<=squatter )[0-9]*(?= is ready)"
finished = r"(?<=squatter )[0-9]*(?= is finished)"

nfinished = 0
server, port = get_available_port(default_port)
@async while true
  let sock = accept(server)
    @async begin
      while isopen(sock) || nb_available(sock)>0
        tmp = chomp(readline(sock,chomp=false))
        length(tmp)==0 && continue
        info(tmp, prefix="DIRECTOR<SQUATTER: ")
        flush(STDOUT);  flush(STDERR)
        if ismatch(ready,tmp)
          m=match(ready,tmp)
          notify(events[parse(Int,m.match),1], sock)
        elseif ismatch(finished,tmp)
          m=match(finished,tmp)
          global nfinished += 1
          notify(events[parse(Int,m.match),2], nfinished)
        end
      end
    end
  end
end

# dispatch sub bounding boxes to squatters,
# in a way which greedily hangs on to nodes instead of re-waiting in the queue
t0=time()
@sync begin
  i = 1
  nextidx() = (global i; idx=i; i+=1; idx)
  for p = 1:nnodes
    events[p,1]=Condition()
    events[p,2]=Condition()

    @async begin
      sock = wait(events[p,1])

      if sock==nothing
        info("deleting squatter ",p, prefix="DIRECTOR: ")
        if which_cluster=="janelia"
          cmd = `bkill $(jobid)\[$p\]`
          try;  run(cmd);  end
        else
          kill(proc[p])
        end
      else
        while isopen(sock)
          jobidx = nextidx()
          if jobidx > length(job_aabbs)
            cmd = "squatter $p terminate"
            println(sock, cmd)
            info(cmd, prefix="DIRECTOR>SQUATTER: ")
            map((x)->notify(events[x,1], nothing), 1:nnodes)
            break
          end
          shape = job_aabbs[jobidx][1]
          cmd = "squatter $p dole out job $(ARGS[1]) $(shape[2][1]) $(shape[2][2]) $(shape[2][3]) $(shape[3][1]) $(shape[3][2]) $(shape[3][3]) $hostname $port"
          println(sock, cmd)
          info(cmd, prefix="DIRECTOR>SQUATTER: ")
          nfinished = wait(events[p,2])
          info("director has finished ",nfinished," of ",length(job_aabbs)," jobs.  ",
                signif(nfinished / length(job_aabbs) * 100,4),"% done", prefix="DIRECTOR: ")
        end
      end
    end
  end

  #launch_workers
  cmd = `umask 002 \;
         $(ENV["JULIA"]) $(ENV["RENDER_PATH"])/src/render/src/squatter.jl $(ARGS[1]) $hostname $port`
  if which_cluster=="janelia"
    queue = short_queue ? `-W 60 -n 16` : `-W 10080 -n 32`
    pcmd = pipeline(`echo $cmd`, `bsub -P $bill_userid $queue -J $(jobname)1\[1-$nnodes\]
          -R"select[avx2]" -o $logfile_scratch/squatter%I.log`)
    info(pcmd, prefix="DIRECTOR: ")
    jobid = match(r"(?<=Job <)[0-9]*", readchomp(pcmd)).match
  else
    proc = Array{Any}(nnodes)
    for n=1:nnodes
      pcmd = `ssh -o StrictHostKeyChecking=no $(which_cluster[n]) export RENDER_PATH=$(ENV["RENDER_PATH"]) \;
            export LD_LIBRARY_PATH=$(ENV["LD_LIBRARY_PATH"]) \;
            export JULIA=$(ENV["JULIA"]) \;
            export HOSTNAME=$(ENV["HOSTNAME"]) \;
            export LSB_JOBINDEX=$n \;
            $cmd \&\> $logfile_scratch/squatter$n.log`
      info(pcmd, prefix="DIRECTOR: ")
      proc[n] = spawn(pcmd)
    end
  end
end
info("squatters took ",round(Int,time()-t0)," sec", prefix="DIRECTOR: ")

#closelibs()

info(readchomp(`date`), prefix="DIRECTOR: ")
