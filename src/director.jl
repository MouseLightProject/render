# bsub'ed by render to one core of a regular compute node
# bsubs a bunch of squatters to gpu and/or cpu nodes
# partitions the bounding box of the tilespace into countof_job sized sub bounding boxes
# parcels out multiple sub bounding boxes to each squatter
# saves stdout/err to <destination>/render.log

# julia director.jl parameters.jl jobname

@info string("DIRECTOR: ",readchomp(`date`))
@info string("DIRECTOR: ",readchomp(`hostname`))

using Sockets

include(ARGS[1])
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

const jobname = ARGS[2]
const tiles = TileBaseOpen(source)
tile_shape = TileShape(TileBaseIndex(tiles,1))
const nchannels = tile_shape[4]

# delete scratch
t0=time()
@info string("DIRECTOR: source = ",source)
@info string("DIRECTOR: destination = ",destination)
mkpath(shared_scratch)
scratch0 = rmcontents(shared_scratch, "after", "DIRECTOR: ")
@info string("DIRECTOR: deleting shared_scratch = ",shared_scratch," at start took ",round(Int,time()-t0)," sec")

# get the max output tile size
tiles_bbox = AABBGet(TileBaseAABB(tiles))
const shape_tiles_nm = tiles_bbox[2]
const nlevels = max(0, ceil(Int,
    log(8, prod(map(Float64,shape_tiles_nm)) / (prod(voxelsize_um)*um2nm^3) / max_pixels_per_leaf) ))
shape_leaf_px_initial = round.(Int, round.(shape_tiles_nm./um2nm./voxelsize_um./2^nlevels, digits=-1, base=2))
# ensure that the leaf volume is divisible by 32*32*4 (for GPU), and
# that each leaf dimension is divisible by leaf_dim_divisible_by (for chunking)
xyz=Array{Int}(undef, 3)
cost=Inf32
const shape_leaf_dim_search_range = -20:2:20
for x=shape_leaf_dim_search_range, y=shape_leaf_dim_search_range, z=shape_leaf_dim_search_range
  if mod(prod(shape_leaf_px_initial+[x,y,z]), 32*32*4)==0 &&
     all(map(x->mod(x,leaf_dim_divisible_by), shape_leaf_px_initial+[x,y,z]).==0) &&
     sum(abs.([x,y,z]))<cost
    global xyz=[x,y,z]
    global cost=sum(abs.([x,y,z]))
    @info string("DIRECTOR: adjusting leaf_shape: cost=",cost," delta_xyz=",xyz)
  end
end
cost==Inf32 && @error("can't find satisfactory shape_leaf_px")
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
  println(f,"const origin_nm = [",join(map(string,tiles_bbox[1]),","),"]")
  for repo in ["render", "mltk-bary"]
    println(f,"const $(replace(repo,'-' =>'_'))_version = \"",git_version(joinpath(ENV["RENDER_PATH"],"src",repo)),"\"")
  end
end
open("$destination/transform.txt","w") do f  # for large volume viewer
  println(f,"ox: ",tiles_bbox[1][1])
  println(f,"oy: ",tiles_bbox[1][2])
  println(f,"oz: ",tiles_bbox[1][3])
  println(f,"sx: ",voxelsize_used_um[1]*um2nm*2^nlevels)
  println(f,"sy: ",voxelsize_used_um[2]*um2nm*2^nlevels)
  println(f,"sz: ",voxelsize_used_um[3]*um2nm*2^nlevels)
  println(f,"nl: ",nlevels+1)
end
cp(joinpath(source,"tilebase.cache.yml"), joinpath(destination,"tilebase.cache.yml"))
cp(joinpath(source,"tilebase.cache.jld2"), joinpath(destination,"tilebase.cache.jld2"))
chmod(joinpath(destination,"tilebase.cache.yml"), 0o660)
chmod(joinpath(destination,"tilebase.cache.jld2"), 0o660)
@info string("DIRECTOR: number of levels = ",nlevels)
@info string("DIRECTOR: shape of output tiles is [",join(map(string,shape_leaf_px),","),"] pixels")
@info string("DIRECTOR: voxel dimensions used to make output tile shape even and volume divisible by 32*32*4: [",
    join(map(string,voxelsize_used_um),",")," microns")

# divide in halves instead of eighths for finer-grained use of RAM and local_scratch
function AABBHalveSubdivision(bbox)
  bbox1 = deepcopy(bbox)
  bbox2 = deepcopy(bbox)
  idx = argmax(bbox[2])
  bbox1[2][idx] = floor(bbox1[2][idx]/2)
  bbox2[2][idx] = ceil(bbox2[2][idx]/2)
  bbox2[1][idx] += bbox1[2][idx]
  bbox1, bbox2
end

function get_job_aabbs(bbox)
  bbox_aabb=AABBMake(3)
  AABBSet(bbox_aabb,bbox[1],bbox[2])
  ntiles=0
  for i=1:TileBaseCount(tiles)
    tile_aabb = TileAABB(TileBaseIndex(tiles,i))
    AABBHit(tile_aabb, bbox_aabb) &&
        (include_origins_outside_roi || (all(AABBGet(tile_aabb)[1] .>= bbox[1]))) &&
        (ntiles+=1)
  end
  if ntiles > max_tilechannels_per_job / nchannels
    map(get_job_aabbs, AABBHalveSubdivision(bbox))
  elseif ntiles>0
    push!(job_aabbs, (bbox, ntiles))
  end
end

job_aabbs = []
tiles_bbox[1][:] = round.(Int,tiles_bbox[1][:] + tiles_bbox[2].*region_of_interest[1])
tiles_bbox[2][:] = round.(Int,tiles_bbox[2][:] .* region_of_interest[2])
get_job_aabbs(tiles_bbox)
sort!(job_aabbs; lt=(x,y)->x[2]<y[2], rev=true)
roi_vol = prod(region_of_interest[2])
@info string("DIRECTOR: ",TileBaseCount(tiles),(roi_vol<1 ? "*"*string(roi_vol) : ""),
      " input tiles each with ",nchannels," channels split into ",length(job_aabbs)," jobs")

include_origins_outside_roi && length(job_aabbs)>1 &&
      @warn("include_origins_outside_roi should be true only when there is just one job")

# initialize tcp communication with squatters
nnodes = min( length(job_aabbs),
              throttle_leaf_njobs,
              which_cluster=="janelia" ? round(Int,ncores_incluster/leaf_ncores_per_job) : length(which_cluster) )
@info string("DIRECTOR: number of cluster nodes used = $nnodes")
events = Array{Condition}(undef, nnodes,2)
hostname = readchomp(`hostname`)
default_port = 2000
ready = r"(?<=squatter )[0-9]*(?= is ready)"
finished = r"(?<=squatter )[0-9]*(?= is finished)"

nfinished = 0
server, port = get_available_port(default_port)
@async while true
  let sock = accept(server)
    @async begin
      while isopen(sock) || bytesavailable(sock)>0
        tmp = chomp(readline(sock,keep=true))
        length(tmp)==0 && continue
        @info string("DIRECTOR<SQUATTER: ",tmp)
        flush(stdout);  flush(stderr)
        if occursin(ready,tmp)
          m=match(ready,tmp)
          notify(events[parse(Int,m.match),1], sock)
        elseif occursin(finished,tmp)
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
  global i = 1
  nextidx() = (global i; idx=i; i+=1; idx)
  for p = 1:nnodes
    events[p,1]=Condition()
    events[p,2]=Condition()

    @async begin
      sock = wait(events[p,1])

      if sock==nothing
        @info string("DIRECTOR: deleting squatter ",p)
        if which_cluster=="janelia"
          cmd = `bkill $(jobid)\[$p\]`
          try;  run(cmd);  catch; end
        else
          kill(proc[p])
        end
      else
        while isopen(sock)
          jobidx = nextidx()
          if which_cluster=="janelia"
            njobs_remaining = max(0, length(job_aabbs)-jobidx)
            bjobs_nlines = chomp(read(pipeline(`bjobs -p $jobid`,`wc -l`), String))
            nnodes_pending = max(0, (parse(Int,bjobs_nlines)-1)>>1)
            nnodes_tokill = nnodes_pending - njobs_remaining
            if nnodes_tokill>0
              @info string("DIRECTOR: ",njobs_remaining, " jobs remaining")
              @info string("DIRECTOR: ",nnodes_pending, " nodes pending")
              map((x)->notify(events[x,1], nothing), nnodes-nnodes_tokill+1 : nnodes)
            end
          end
          if jobidx > length(job_aabbs)
            cmd = "squatter $p terminate"
            println(sock, cmd)
            @info string("DIRECTOR>SQUATTER: ",cmd)
            map((x)->notify(events[x,1], nothing), 1:nnodes)
            break
          end
          ori, shape = job_aabbs[jobidx][1]
          cmd = "squatter $p dole out job $(ARGS[1]) $(ori[1]) $(ori[2]) $(ori[3]) $(shape[1]) $(shape[2]) $(shape[3]) $hostname $port"
          println(sock, cmd)
          @info string("DIRECTOR>SQUATTER: ",cmd)
          nfinished = wait(events[p,2])
          @info string("DIRECTOR: director has finished ",nfinished," of ",length(job_aabbs)," jobs.  ",
                round(nfinished / length(job_aabbs) * 100, sigdigits=4),"% done")
        end
      end
    end
  end

  #launch_workers
  cmd = `umask 002 \;
         $(ENV["JULIA"]) $(ENV["RENDER_PATH"])/src/render/src/squatter.jl $(ARGS[1]) $hostname $port`
  if which_cluster=="janelia"
    pcmd = pipeline(`echo $cmd`, `bsub -P $bill_userid -J $(jobname)1\[1-$nnodes\]
          -R"select[avx2]" -W $leaf_time_limit -n $(leaf_ncores_per_job)
          -o $logfile_scratch/squatter%I.log`)
    @info string("DIRECTOR: ",pcmd)
    jobid = match(r"(?<=Job <)[0-9]*", readchomp(pcmd)).match
  else
    proc = Array{Any}(undef, nnodes)
    for n=1:nnodes
      pcmd = `ssh -o StrictHostKeyChecking=no $(which_cluster[n]) export RENDER_PATH=$(ENV["RENDER_PATH"]) \;
            export JULIA=$(ENV["JULIA"]) \;
            export JULIA_PROJECT=$(ENV["JULIA_PROJECT"]) \;
            export HOSTNAME=$(ENV["HOSTNAME"]) \;
            export LSB_JOBINDEX=$n \;
            $cmd \&\> $logfile_scratch/squatter$n.log`
      @info string("DIRECTOR: ",pcmd)
      proc[n] = run(pcmd, wait=false)
    end
  end
end
@info string("DIRECTOR: squatters took ",round(Int,time()-t0)," sec")

#closelibs()

@info string("DIRECTOR: ",readchomp(`date`))
