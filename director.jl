# qsub'ed by render to one core of a regular compute node
# qsubs a bunch of squatters to gpu and/or cpu nodes
# partitions the bounding box of the tilespace into countof_job sized sub bounding boxes
# parcels out multiple sub bounding boxes to each squatter
# parcels out inter-node merge threads to squatters
# saves stdout/err to <destination>/render.log

# julia director.jl parameters.jl jobname

info(readchomp(`date`))
info(readchomp(`hostname`))

include(ARGS[1])
include(ENV["RENDER_PATH"]*"/src/render/admin.jl")

const jobname = ARGS[2]
const tiles = TileBaseOpen(source)
const tile_type = ndtype(TileShape(TileBaseIndex(tiles,1)))

# email user
cmd = `echo watch -n 60 tail -n \$((LINES-1)) $destination/monitor.log` |> `mail -s "job $jobname started" $notify_addr`
info(string(cmd))
run(cmd)

# delete scratch
t0=time()
info("source = ",source)
info("destination = ",destination)
mkpath(shared_scratch)
scratch0 = rmcontents(shared_scratch, "after")
info("deleting shared_scratch = ",shared_scratch," at start took ",string(iround(time()-t0))," sec")

# get the max output tile size
tiles_bbox = AABBGetJ(TileBaseAABB(tiles))
const shape_tiles_nm = tiles_bbox[3]
const nlevels = iceil( log(8, prod(float64(shape_tiles_nm)) / (prod(voxelsize_um)*um2nm^3) / countof_leaf) )
shape_leaf_tmp = int(round(shape_tiles_nm./um2nm./voxelsize_um./2^nlevels,-1,2))
# there must be better ways to ensure
# that prod(shape_leaf_px) is divisible by 32*32*4, and
# that each element is even
xyz=Array(Int,3)
cost=Inf32
for x=-20:2:20, y=-20:2:20, z=-20:2:20
  if mod(prod(shape_leaf_tmp+[x,y,z]),32*32*4)==0 && sum(abs([x,y,z]))<cost
    xyz=[x,y,z]
    cost=sum(abs([x,y,z]))
  end
end
cost==Inf32 && error("can't find satisfactory shape_leaf_px")
const shape_leaf_px = shape_leaf_tmp+xyz
const voxelsize_used_um = shape_tiles_nm./um2nm./2^nlevels ./ shape_leaf_px
open("$destination/calculated_parameters.jl","w") do f
  println(f,"const jobname = \"",jobname,"\"")
  println(f,"const nlevels = ",nlevels)
  println(f,"const shape_leaf_px = [",join(map(string,shape_leaf_px),","),"]")
  println(f,"const voxelsize_used_um = ",voxelsize_used_um)
  println(f,"const origin_nm = [",join(map(string,tiles_bbox[2]),","),"]")
  println(f,"const tile_type = convert(Cint,$tile_type)")
  println(f,"const render_version = \"", readchomp(`git --git-dir=$(dirname(Base.source_path()))/.git log -1 --pretty=format:"%ci %H"`),"\"")
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
info("number of levels = ",string(nlevels))
info("shape of output tiles is [",join(map(string,shape_leaf_px),","),"] pixels")
info("voxel dimensions used to make output tile shape even and volume divisible by 32*32*4: [",join(map(string,voxelsize_used_um),",")," microns")

# divide in halves instead of eighths for finer-grained use of local_scratch
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
  if prod(float64(bbox[3])) / (prod(voxelsize_used_um)*um2nm^3) > countof_job
    map(get_job_aabbs, AABBHalveSubdivision(bbox))
  else
    push!(job_aabbs, bbox)
  end
end

job_aabbs = {}
tiles_bbox[2][:] = int(tiles_bbox[2][:] + tiles_bbox[3].*region_of_interest[1])
tiles_bbox[3][:] = int(tiles_bbox[3][:] .* region_of_interest[2])
get_job_aabbs(tiles_bbox)
roi_vol = prod(region_of_interest[2])
info(string(TileBaseCount(tiles)),(roi_vol<1 ? " * "*string(roi_vol): "")," tiles with ",string(nchannels)," channels split into ",string(nchannels*length(job_aabbs))," jobs")

TileBaseClose(tiles)

# initialze tcp communication with squatters
nproc = nk20 + n570 + ncpu
events = Array(Condition,nproc,2)
hostname = readchomp(`hostname`)
port = 2000
ready = r"(?<=squatter )[0-9]*(?= is ready)"
finished = r"(?<=squatter )[0-9]*(?= is finished)"

nfinished = 0
@async begin
  sock = Any[]
  server = listen(port)
  while true
    push!(sock, accept(server))
    @async let sock=sock[end]
      while isopen(sock) || nb_available(sock)>0
        tmp = chomp(readline(sock))
        length(tmp)==0 && continue
        println("DIRECTOR<SQUATTER: ",tmp)
        flush(STDOUT);  flush(STDERR)
        if ismatch(ready,tmp)
          m=match(ready,tmp)
          notify(events[int(m.match),1], sock)
        elseif ismatch(finished,tmp)
          m=match(finished,tmp)
          global nfinished += 1
          notify(events[int(m.match),2], nfinished)
        end
      end
    end
  end
end

# dispatch sub bounding boxes to squatters,
# in a way which greedily hangs on to nodes instead of re-waiting in the queue
jobids = String[]

function launch_workers(t1,t2,queue,envpath)
  cmd = `qsub -A $bill_userid -t $t1-$t2 $queue -N $jobname -b y -j y -V -shell n -o $destination/'$TASK_ID.log'
        $(ENV["RENDER_PATH"])$(envpath)/bin/julia $(ENV["RENDER_PATH"])/src/render/squatter.jl $(ARGS[1]) $hostname $port`
  info(string(cmd))
  push!(jobids, match(r"(?<=job-array )[0-9]*", readchomp(cmd)).match)
end

t0=time()
merge_procs = Any[]
@sync begin
  i = 1
  nextidx() = (idx=i; i+=1; idx)
  for p = 1:nproc
    events[p,1]=Condition()
    events[p,2]=Condition()

    @async begin
      sock = wait(events[p,1])
      if sock==nothing
        cmd = `qdel $(p<=nk20 ? jobids[1] : p<=(nk20+n570) ? jobids[2] : jobids[3]).$p`
        info("deleting squatter ",string(p),": ",string(cmd))
        try;  run(cmd);  end
      else
        while isopen(sock)
          p>nk20 && sleep(10)  # favor faster nodes
          p>(nk20+ncpu) && sleep(10)
          idx = nextidx()
          tmp = find(map((x)->x[1]==p, merge_procs))
          if idx > nchannels*length(job_aabbs)
            if length(tmp)==0 || length(merge_procs)>8*nchannels
              deleteat!(merge_procs, tmp)
              cmd = "squatter $p terminate"
              println("DIRECTOR>SQUATTER: ",string(cmd))
              println(sock, cmd)
            end
            map((x)->notify(events[x,1], nothing), 1:nproc)
            break
          end
          length(tmp)==0 && push!(merge_procs, (p, sock))
          channel = (idx-1)%2+1
          shape = job_aabbs[(idx+1)>>1]
          cmd = "squatter $p dole out job $(ARGS[1]) $channel $(shape[2][1]) $(shape[2][2]) $(shape[2][3]) $(shape[3][1]) $(shape[3][2]) $(shape[3][3]) $hostname $port"
          println("DIRECTOR>SQUATTER: ",string(cmd))
          println(sock, cmd)
          nfinished = wait(events[p,2])
          info("director has finished ",string(nfinished)," of ",string(nchannels*length(job_aabbs))," jobs.  ",string(signif(nfinished / (nchannels*length(job_aabbs)) * 100,7,2)),"% done")
        end
      end
    end
  end

  nk20>0 && launch_workers(1, nk20, ["-l", "gpu_k20=true", "-pe", "batch", "16"],"/env/k20")
  ncpu>0 && launch_workers(nk20+1, nk20+ncpu, ["-l", "haswell=true", "-pe", "batch", "32"],"/env/cpu")
  n570>0 && launch_workers(nk20+ncpu+1, nk20+ncpu+n570, ["-l", "gpu=true", "-pe", "batch", "7"],"/env/570")
end
info("squatters took ",string(iround(time()-t0))," sec")

# merge output tiles when done, and build octree
t0=time()
info("director is merging output tiles with ",string(length(merge_procs))," nodes")
@sync begin
  i = 1
  nextidx() = (idx=i; i+=1; idx)
  for p = 1:length(merge_procs)
    @async begin
      while isopen(merge_procs[p][2])
        idx = nextidx()
        if idx > 64*nchannels || nlevels <= 2
          cmd = "squatter $(merge_procs[p][1]) terminate"
          println("DIRECTOR>SQUATTER: ",string(cmd))
          println(merge_procs[p][2], cmd)
          break
        end
        channel = (idx-1)%2+1
        octant = (idx-1)>>4+1
        octant2 = ((idx-1)>>1)%8+1
        isdir(joinpath(shared_scratch,string(octant),string(octant2))) || continue
        cmd = "squatter $(merge_procs[p][1]) merge merge_output_tiles(\"$shared_scratch\", \"$destination\", \"default\", \"$("."*string(channel-1)*".tif")\", \"$(string(octant))/$(string(octant2))\", true, true, false)"
        println("DIRECTOR>SQUATTER: ",string(cmd))
        println(merge_procs[p][2], cmd)
        wait(events[merge_procs[p][1],2])
      end
    end
  end
end
for channel=1:nchannels
  merge_output_tiles(nlevels>2 ? destination : shared_scratch, destination, "default", "."*string(channel-1)*".tif", "", true, true, false)
end
info("inter-node merge and octree took ",string(iround(time()-t0))," sec")

# delete shared_scratch
t0=time()
scratch1 = rmcontents(shared_scratch, "before")
info("deleting shared_scratch at end took ",string(iround(time()-t0))," sec")
info("director has finished using ",string(signif((scratch0-scratch1)/1024/1024,4,2))," GB of shared_scratch")

# email user
cmd = `echo destination = $destination` |> `mail -s "job $jobname finished" $notify_addr`
info(string(cmd))
run(cmd)

closelibs()

info(readchomp(`date`))

# write protect
run(`chmod -R a-w $destination`)
