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

type NDException <: Exception end

write = "manager tells peon for input tile "*ARGS[4]*" to write output tile"
send = "manager tells peon for input tile "*ARGS[4]*" to send output tile"

# 2 -> sizeof(Uint16), 20e3 -> .tif metadata size, 15 -> max # possible concurrent saves, need to generalize
enough_free(path) = int(split(readall(`df $path`))[11])*1024 > 15*((prod(shape_leaf_px)*2 + 20e3))

function depth_first_traverse(bbox,out_tile_path)
  cboxes = AABBBinarySubdivision(bbox)

  global out_tile_ws, time_transforming, time_saving, time_downsampling

  for i=1:8
    AABBHit(cboxes[i], TileAABB(tile))==1 || continue
    out_tile_path_next = joinpath(out_tile_path,string(i))

    if !isleaf(cboxes[i])
      depth_first_traverse(cboxes[i],out_tile_path_next)
    else
      info("processing output tile ",out_tile_path_next)

      t0=time()
      const origin_nm = AABBGetJ(cboxes[i])[2]
      const transform = (transform_nm .- origin_nm) ./ (voxelsize_used_um*um2nm)

      try
        ndfill(out_tile_ws, 0x0000)
      catch
        error("in peon/ndfill")
      end
      try
        if !isnan(thisgpu)
          BarycentricGPUdestination(resampler, nddata(out_tile_ws))
          BarycentricGPUresample(resampler, convert(Array{Float32}, transform))
          BarycentricGPUresult(resampler, nddata(out_tile_ws))
        else
          BarycentricCPUdestination(resampler, nddata(out_tile_ws))
          BarycentricCPUresample(resampler, convert(Array{Float32}, transform))
          BarycentricCPUresult(resampler, nddata(out_tile_ws))
        end
      catch
        error("BarycentricDestination/Resample/Result error:  GPU $thisgpu, input tile $in_tile_idx")
      end
      time_transforming+=(time()-t0)

      t0=time()
      println(sock, "peon for input tile ",ARGS[4]," has output tile ",out_tile_path_next," ready")
      local tmp
      while true
        tmp = chomp(readline(sock))
        length(tmp)==0 || break
      end
      println("PEON<MANAGER: ",tmp)
      if startswith(tmp,send)
        try
          println(sock,"peon for input tile ",ARGS[4]," will send output tile ",out_tile_path_next)
          serialize(sock, out_tile)
        end
      elseif startswith(tmp,write)
        if enough_free(local_scratch)
          save_out_tile(local_scratch, out_tile_path_next, string(in_tile_idx)*".$(channel-1).tif", out_tile_ws)
          try;  println(sock,"peon for input tile ",ARGS[4]," wrote output tile ",out_tile_path_next," to local_scratch");  end
        else
          save_out_tile(shared_scratch, out_tile_path_next, ARGS[29]*"."*string(in_tile_idx)*".$(channel-1).tif", out_tile_ws)
          msg = "peon for input tile "*string(ARGS[4])*" wrote output tile "*out_tile_path_next*" to shared_scratch"
          try;  println(sock,msg);  end
          warn(msg)
        end
      end
      time_saving+=(time()-t0)
    end

    try
      AABBFree(cboxes[i])
    catch
      error("in peon/AABBFree")
    end
  end
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

    global out_tile_ws = ndalloc(shape_leaf_px, ndtype(in_tile_ws))
    global out_tile = pointer_to_array(convert(Ptr{Uint16},nddata(out_tile_ws)), tuple(shape_leaf_px...))
  catch
    error("in peon/ndalloc")
  end

  t1=time()
  try
    global resampler = Ptr{Void}[0]
    if !isnan(thisgpu)
      cudaSetDevice(thisgpu)
      info("initializing GPU ",string(thisgpu),", ",string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
      BarycentricGPUinit(resampler, ndshape(in_tile_ws), ndshape(out_tile_ws), 3)
      BarycentricGPUsource(resampler, nddata(in_tile_ws))
      info("initialized GPU ",string(thisgpu),", ",string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
    else
      BarycentricCPUinit(resampler, ndshape(in_tile_ws), ndshape(out_tile_ws), 3)
      BarycentricCPUsource(resampler, nddata(in_tile_ws))
    end
  catch
    error("BarycentricInit error:  GPU $thisgpu, input tile $in_tile_idx")
  end
  info("transform initialization for input tile ",string(in_tile_idx)," took ",string(iround(time()-t1))," sec")

  depth_first_traverse(TileBaseAABB(tiles),"")
  try
    ndfree(out_tile_ws)
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
  info("saving output tiles for input tile ",string(in_tile_idx)," took ",string(iround(time_saving))," sec")
  info("downsampling output tiles for input tile ",string(in_tile_idx)," took ",string(iround(time_downsampling))," sec")
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
