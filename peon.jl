# spawned by manager
# processes all output tiles, both leaf and downsampled, from a given input tile
# saves stdout/err to <destination>/[0-9]*.log

# julia peon.jl parameters.jl gpu channel in_tile transform[1-24] origin_str hostname port

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(ENV["RENDER_PATH"]*"/src/render/admin.jl")

time_transforming=0.0
time_saving=0.0
time_downsampling=0.0

# keep boss informed
sock = connect(ARGS[30],int(ARGS[31]))

# sort(reshape(arg,8))[7] but half the time and a third the memory usage
function seven(arg::Array{Uint16,3})
  m0::Uint16 = 0x0000
  m1::Uint16 = 0x0000
  for i = 1:8
    @inbounds tmp::Uint16 = arg[i]
    if tmp>m0
      m1=m0
      m0=tmp
    elseif tmp>m1
      m1=tmp
    end
  end
  m1
end

type NDException <: Exception end

write = "manager tells peon for input tile "*ARGS[4]*" to write output tile"
send = "manager tells peon for input tile "*ARGS[4]*" to send output tile"

function save2ramORscratch(level)
  println(sock, "peon for input tile ",ARGS[4]," has output tile ",join(out_tile_path, Base.path_separator)," ready")
  local tmp
  while true
    tmp = chomp(readline(sock))
    length(tmp)==0 || break
  end
  println("PEON<MANAGER: ",tmp)
  if startswith(tmp,write)
    out_tile_path_str = join(out_tile_path, Base.path_separator)
    if save_out_tile(local_scratch, out_tile_path_str, string(in_tile_idx)*".$(channel-1).tif", out_tiles_ws[level])
      try;  println(sock,"peon for input tile ",ARGS[4]," wrote output tile ",out_tile_path_str," to local_scratch");  end
    elseif save_out_tile(shared_scratch, out_tile_path_str, ARGS[29]*"."*string(in_tile_idx)*".$(channel-1).tif", out_tiles_ws[level])
      msg = "peon for input tile "*string(ARGS[4])*" wrote output tile "*out_tile_path_str*" to shared_scratch"
      try;  println(sock,msg);  end
      warn(msg)
    else
      error("peon for input tile "*ARGS[4]*" can't write "*joinpath(string(in_tile_idx)*".$(channel-1).tif")*"anywhere.  all disks full")
    end
  elseif startswith(tmp,send)
    try
      println(sock,"peon for input tile ",ARGS[4]," will send output tile ",join(out_tile_path, Base.path_separator))
      serialize(sock, out_tiles[level])
    end
  else
    error("invalid message from manager to peon")
  end
end

out_tile_path=Int[]

function depth_first_traverse(bbox)
  cboxes = AABBBinarySubdivision(bbox)

  global out_tiles_ws, out_tile_path, time_transforming, time_saving, time_downsampling

  const level = length(out_tile_path)+1
  try
    ndfill(out_tiles_ws[level], 0x0000)
  catch
    error("in peon/ndfill")
  end

  for i=1:8
    AABBHit(cboxes[i], TileAABB(tile))==1 || continue
    push!(out_tile_path,i)

    const origin_nm = AABBGetJ(cboxes[i])[2]
    const transform = (transform_nm .- origin_nm) ./ (voxelsize_used_um*um2nm)

    if !isleaf(cboxes[i])
      depth_first_traverse(cboxes[i])
    else
      info("processing output tile ",string(out_tile_path))

      t0=time()
      try
        ndfill(out_tiles_ws[level+1], 0x0000)
      catch
        error("in peon/ndfill2")
      end
      try
        if !isnan(thisgpu)
          BarycentricGPUdestination(resampler, nddata(out_tiles_ws[level+1]))
          BarycentricGPUresample(resampler, convert(Array{Float32}, transform))
          BarycentricGPUresult(resampler, nddata(out_tiles_ws[level+1]))
        else
          BarycentricCPUdestination(resampler, nddata(out_tiles_ws[level+1]))
          BarycentricCPUresample(resampler, convert(Array{Float32}, transform))
          BarycentricCPUresult(resampler, nddata(out_tiles_ws[level+1]))
        end
      catch
        error("BarycentricDestination/Resample/Result error:  GPU $thisgpu, input tile $in_tile_idx")
      end
      time_transforming+=(time()-t0)

      t0=time()
      save2ramORscratch(level+1)
      time_saving+=(time()-t0)
    end

    try
      t0=time()
      out_tiles[level][ (((i-1)>>0)&1 * shape_leaf_px[1]>>1) + (1:shape_leaf_px[1]>>1),
                        (((i-1)>>1)&1 * shape_leaf_px[2]>>1) + (1:shape_leaf_px[2]>>1),
                        (((i-1)>>2)&1 * shape_leaf_px[3]>>1) + (1:shape_leaf_px[3]>>1) ] =
          [ seven(out_tiles[level+1][x:x+1,y:y+1,z:z+1]) for x=1:2:shape_leaf_px[1]-1, y=1:2:shape_leaf_px[2]-1, z=1:2:shape_leaf_px[3]-1 ]
      time_downsampling+=(time()-t0)
    catch
      error("in peon/seven")
    end

    pop!(out_tile_path)
    try
      AABBFree(cboxes[i])
    catch
      error("in peon/AABBFree")
    end
  end

  t0=time()
  save2ramORscratch(level)
  time_saving+=(time()-t0)
end

function process_tile(thisgpu_, in_tile_idx_, transform_)
  t0=time()

  global thisgpu = thisgpu_
  global in_tile_idx = in_tile_idx_
  global transform_nm = transform_

  local tiles
  try
    tiles = TileBaseOpen(source)
    global tile = TileBaseIndex(tiles, in_tile_idx)
  catch
    error("in peon/TileBaseOpen-Index")
  end

  info("processing input tile $in_tile_idx: ",bytestring(TilePath(tile)))

  try
    t1=time()
    tmp = TileShape(tile)
    global in_tile_ws = ndalloc(ndshapeJ(tmp), ndtype(tmp))
    tmp=split(bytestring(TilePath(tile)),"/")
    push!(tmp, tmp[end]*"-$file_infix."*string(channel-1)*".tif")
    ndioClose(ndioRead(ndioOpen("/"*joinpath(tmp...), C_NULL, "r"), in_tile_ws))
    info("reading input tile ",string(in_tile_idx)," took ",string(iround(time()-t1))," sec")

    global out_tiles_ws = Array(Ptr{Void}, nlevels+1)
    global out_tiles = Array(Array{Uint16,3}, nlevels+1)
    for i=1:nlevels+1
      out_tiles_ws[i] = ndalloc(shape_leaf_px, ndtype(in_tile_ws))
      out_tiles[i] = pointer_to_array(convert(Ptr{Uint16},nddata(out_tiles_ws[i])), tuple(shape_leaf_px...))
    end
  catch
    error("in peon/ndalloc")
  end

  t1=time()
  try
    global resampler = Ptr{Void}[0]
    if !isnan(thisgpu)
      cudaSetDevice(thisgpu)
      info("initializing GPU ",string(thisgpu),", ",string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
      BarycentricGPUinit(resampler, ndshape(in_tile_ws), ndshape(out_tiles_ws[1]), 3)
      BarycentricGPUsource(resampler, nddata(in_tile_ws))
      info("initialized GPU ",string(thisgpu),", ",string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
    else
      BarycentricCPUinit(resampler, ndshape(in_tile_ws), ndshape(out_tiles_ws[1]), 3)
      BarycentricCPUsource(resampler, nddata(in_tile_ws))
    end
  catch
    error("BarycentricInit error:  GPU $thisgpu, input tile $in_tile_idx")
  end
  info("transform initialization for input tile ",string(in_tile_idx)," took ",string(iround(time()-t1))," sec")

  depth_first_traverse(TileBaseAABB(tiles))
  try
    map(ndfree, out_tiles_ws)
    ndfree(in_tile_ws)
  catch
    error("in peon/ndfree")
  end

  try
    #TileFree(tile)
    TileBaseClose(tiles)
  catch
    error("peon/TileBaseClose")
  end

  try
    if !isnan(thisgpu)
      info("releasing GPU ",string(thisgpu),", ",string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
      BarycentricGPUrelease(resampler)
      info("released GPU ",string(thisgpu),", ",string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
    else
      BarycentricCPUrelease(resampler)
    end
  catch
    error("BarycentricRelease error:  GPU $thisgpu, input tile $in_tile_idx")
  end

  info("transforming input tile ",string(in_tile_idx)," took ",string(iround(time_transforming))," sec")
  info("saving output tiles ",string(in_tile_idx)," took ",string(iround(time_saving))," sec")
  info("downsampling output tiles ",string(in_tile_idx)," took ",string(iround(time_downsampling))," sec")
  info("input tile ",string(in_tile_idx)," took ",string(iround(time()-t0))," sec overall")
end

const local_scratch="/scratch/"*readchomp(`whoami`)
const channel = int(ARGS[3])

process_tile(ARGS[2]=="NaN" ? NaN : int(ARGS[2]), int(ARGS[4]), reshape(int(ARGS[5:28]),3,8))

# keep boss informed
try
  println(sock,"peon for input tile ",ARGS[4]," is finished")
  close(sock)
end
