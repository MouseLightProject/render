# spawned by manager
# processes all leaf output tiles from a given input tile
# for outputs with more than one input, sends results back to manager vi tcp
#    (or saves to local_scratch if needed), otherwise saves to shared_scratch
# saves stdout/err to <destination>/[0-9]*.log

# julia peon.jl parameters.jl gpu channel in_tile origin_str solo_out_tiles hostname port nxlims xlims nylims ylims zlims dims[1:3] transform[1-3*2*(n+1)^2]

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(ENV["RENDER_PATH"]*"/src/render/admin.jl")

time_initing=0.0
time_transforming=0.0
time_saving=0.0
time_waiting=0.0

# keep boss informed
sock = connect(ARGS[7],int(ARGS[8]))

type NDException <: Exception end

const write = "manager tells peon for input tile "*ARGS[4]*" to write output tile"
const send = "manager tells peon for input tile "*ARGS[4]*" to send output tile"
const receive = "manager tells peon for input tile "*ARGS[4]*" to receive output tile"

# 2 -> sizeof(Uint16), 20e3 -> .tif metadata size, 15 -> max # possible concurrent saves, need to generalize
enough_free(path) = int(split(readall(`df $path`))[11])*1024 > 15*((prod(shape_leaf_px)*2 + 20e3))

function depth_first_traverse(bbox, out_tile_path, sub_tile_str, sub_transform_nm, orientation, in_subtile_aabb)
  cboxes = AABBBinarySubdivision(bbox)

  global out_tiles_ws, out_tiles_jl, time_transforming, time_saving, time_waiting

  for i=1:8
    AABBHit(cboxes[i], in_subtile_aabb)==1 || continue
    out_tile_path_next = joinpath(out_tile_path,string(i))

    if !isleaf(cboxes[i])
      depth_first_traverse(cboxes[i], out_tile_path_next, sub_tile_str, sub_transform_nm, orientation, in_subtile_aabb)
    else
      info("processing output tile ",out_tile_path_next)

      t0=time()
      const origin_nm = AABBGetJ(cboxes[i])[2]
      const transform = (sub_transform_nm .- origin_nm) ./ (voxelsize_used_um*um2nm)

      if !haskey(out_tiles_ws,out_tile_path_next)
        out_tiles_ws[out_tile_path_next] = ndalloc(shape_leaf_px, data_type)
        out_tiles_jl[out_tile_path_next] = pointer_to_array(convert(Ptr{Uint16},
              nddata(out_tiles_ws[out_tile_path_next])), tuple(shape_leaf_px...))
        ndfill(out_tiles_ws[out_tile_path_next], 0x0000)
        tmp = map(x->AABBHit(cboxes[i], x), in_subtiles_aabb)
        merge_count[out_tile_path_next]=Uint8[ sum(tmp), 0 ]
      end

      if !isnan(thisgpu)
        BarycentricGPUdestination(resampler, nddata(out_tiles_ws[out_tile_path_next]))
        BarycentricGPUresample(resampler, convert(Array{Float32}, transform))
        BarycentricGPUresult(resampler, nddata(out_tiles_ws[out_tile_path_next]))
      else
        BarycentricCPUdestination(resampler, nddata(out_tiles_ws[out_tile_path_next]))
        BarycentricCPUresample(resampler, convert(Array{Float32}, transform), orientation, interpolation)
        BarycentricCPUresult(resampler, nddata(out_tiles_ws[out_tile_path_next]))
      end
      time_transforming+=(time()-t0)

      merge_count[out_tile_path_next][2]+=1
      if merge_count[out_tile_path_next][2]==merge_count[out_tile_path_next][1]
        t0=time()
        if out_tile_path_next in solo_out_tiles
          save_out_tile(shared_scratch, out_tile_path_next, ARGS[5]*".$(channel-1).tif",
              out_tiles_ws[out_tile_path_next])
          info("peon transfered output tile ",out_tile_path_next," from RAM to shared_scratch")
        else
          println(sock, "peon for input tile ",ARGS[4]," has output tile ",out_tile_path_next," ready")
          t1=time()
          local tmp
          while true
            tmp = chomp(readline(sock))
            length(tmp)==0 || break
          end
          time_waiting+=(time()-t1)
          println(STDERR,"PEON<MANAGER: ",tmp)
          if startswith(tmp,send)
            println(sock,"peon for input tile ",ARGS[4]," will send output tile ",out_tile_path_next)
            serialize(sock, out_tiles_jl[out_tile_path_next])
          elseif startswith(tmp,receive)
            out_tiles_jl[out_tile_path_next][:] = max(out_tiles_jl[out_tile_path_next]::Array{Uint16,3},
                deserialize(sock)::Array{Uint16,3})
            save_out_tile(shared_scratch, out_tile_path_next, ARGS[5]*".$(channel-1).tif",
                out_tiles_ws[out_tile_path_next])
            println(sock,"peon for input tile ",ARGS[4]," saved output tile ",out_tile_path_next)
            info("peon transfered output tile ",out_tile_path_next," from RAM to shared_scratch")
          elseif startswith(tmp,write)
            if enough_free(local_scratch)
              save_out_tile(local_scratch, out_tile_path_next,
                  string(in_tile_idx)*"."*sub_tile_str*".$(channel-1).tif", out_tiles_ws[out_tile_path_next])
              println(sock,"peon for input tile ",ARGS[4]," wrote output tile ",out_tile_path_next," to local_scratch")
            else
              save_out_tile(shared_scratch, out_tile_path_next,
                  ARGS[5]*"."*string(in_tile_idx)*"."*sub_tile_str*".$(channel-1).tif",
                  out_tiles_ws[out_tile_path_next])
              msg = "peon for input tile "*string(ARGS[4])*" wrote output tile "*out_tile_path_next*" to shared_scratch"
              println(sock,msg)
              warn(msg)
            end
          end
        end
        time_saving+=(time()-t0)
      end
    end

    AABBFree(cboxes[i])
  end
end

function process_tile()
  t0=time()

  global time_initing

  local tiles
  try
    tiles = TileBaseOpen(source)
    global tile = TileBaseIndex(tiles, in_tile_idx)
  catch
    error("in peon/TileBaseOpen-Index")
  end

  info("processing input tile $in_tile_idx: ",bytestring(TilePath(tile)))

  local in_tile_ws, in_tile_jl, in_subtile_ws, in_subtile_jl
  try
    t1=time()
    tmp = TileShape(tile)
    shape_intile = ndshapeJ(tmp)
    global data_type = ndtype(tmp)
    in_tile_ws = ndalloc(shape_intile, data_type)
    in_tile_jl = pointer_to_array(convert(Ptr{Uint16},nddata(in_tile_ws)), tuple(shape_intile...))
    in_subtile_ws = ndalloc([xlims[2]-xlims[1]+1,ylims[2]-ylims[1]+1,zlims[2]-zlims[1]+1], data_type, false)
    tmp=split(bytestring(TilePath(tile)),"/")
    push!(tmp, tmp[end]*"-$file_infix."*string(channel-1)*".tif")
    ndioClose(ndioRead(ndioOpen("/"*joinpath(tmp...), C_NULL, "r"), in_tile_ws))
    info("reading input tile ",string(in_tile_idx)," took ",string(iround(time()-t1))," sec")
  catch
    error("in peon/ndalloc")
  end

  global in_subtiles_aabb = calc_in_subtiles_aabb(tile,xlims,ylims,transform_nm)

  # for each input subtile, recursively traverse the output tiles
  shape_leaf_ptr = pointer(convert(Array{Cuint,1},shape_leaf_px))
  for ix=1:length(xlims)-1, iy=1:length(ylims)-1
    info("processing transform ",string(xlims[ix:ix+1])*"-"*string(ylims[iy:iy+1]),
        " for input tile ",string(in_tile_idx))
    t1=time()
    in_subtile_jl = in_tile_jl[1+(xlims[ix]:xlims[ix+1]),1+(ylims[iy]:ylims[iy+1]),1+(zlims[1]:zlims[2])]
    ndref(in_subtile_ws, pointer(in_subtile_jl), convert(Cint,0))
    try
      global resampler = Ptr{Void}[0]
      if !isnan(thisgpu)
        cudaSetDevice(thisgpu)
        info("initializing GPU ",string(thisgpu),", ",
            string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
        BarycentricGPUinit(resampler, ndshape(in_subtile_ws), shape_leaf_ptr , 3)
        BarycentricGPUsource(resampler, nddata(in_subtile_ws))
        info("initialized GPU ",string(thisgpu),", ",
            string(signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2))," GB free")
      else
        BarycentricCPUinit(resampler, ndshape(in_subtile_ws), shape_leaf_ptr, 3)
        BarycentricCPUsource(resampler, nddata(in_subtile_ws))
      end
    catch
      error("BarycentricInit error:  GPU $thisgpu, input tile $in_tile_idx")
    end
    time_initing+=(time()-t1)

    depth_first_traverse(TileBaseAABB(tiles), "", string(ix)*"x"*string(iy),
        transform_nm[:,subtile_corner_indices(ix,iy)],
        isodd(ix+iy) ? 0 : 90,
        in_subtiles_aabb[ix,iy])
  end

  ndfree(in_tile_ws)

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

  info("initializing input tile ",string(in_tile_idx), " took ",string(iround(time_initing))," sec")
  info("transforming input tile ",string(in_tile_idx)," took ",string(iround(time_transforming))," sec")
  info("saving output tiles for input tile ",string(in_tile_idx)," took ",string(iround(time_saving))," sec")
  info("waiting for manager for input tile ",string(in_tile_idx)," took ",string(iround(time_waiting))," sec")
  info("input tile ",string(in_tile_idx)," took ",string(iround(time()-t0))," sec overall")
end

const local_scratch="/scratch/"*readchomp(`whoami`)
const channel = int(ARGS[3])
const solo_out_tiles = eval(parse(ARGS[6]))
const thisgpu = ARGS[2]=="NaN" ? NaN : int(ARGS[2])
const in_tile_idx = int(ARGS[4])
idx = 9
const xlims = int(ARGS[idx+(1:int(ARGS[idx]))])
idx += length(xlims)+1
const ylims = int(ARGS[idx+(1:int(ARGS[idx]))])
idx += length(ylims)+1
const zlims = int(ARGS[idx:idx+1])
idx += length(zlims)
const dims = -1+int(ARGS[idx:idx+2])
idx += length(dims)
const transform_nm = reshape(int(ARGS[idx:end]),3,length(xlims)*length(ylims)*2)

const out_tiles_ws = Dict{ASCIIString,Ptr{Void}}()
const out_tiles_jl = Dict{ASCIIString,Array{Uint16,3}}()
const merge_count = Dict{ASCIIString,Array{Uint8,1}}()

@assert all(diff(diff(xlims)).==0)
@assert all(diff(diff(ylims)).==0)

process_tile()

for (k,v) in merge_count
  info(string((k,v)))
  v[1]>1 && v[1]!=v[2] && warn("not all input subtiles processed for output tile ",string(k)," : ",string(v))
end

map(ndfree,values(out_tiles_ws))
map(AABBFree,in_subtiles_aabb)

closelibs()

# keep boss informed
println(sock,"peon for input tile ",ARGS[4]," is finished")
close(sock)
