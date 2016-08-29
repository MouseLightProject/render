# spawned by manager
# processes all leaf output tiles from a given input tile
# for outputs with more than one input, sends results back to manager vi tcp
#    (or saves to local_scratch if needed), otherwise saves to shared_scratch
# saves stdout/err to <destination>/[0-9]*.log

# julia peon.jl parameters.jl gpu channel in_tile origin_str solo_out_tiles hostname port nxlims xlims nylims ylims nzlims zlims dims[1:3] transform[1-3*2*(n+1)^2]

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(ENV["RENDER_PATH"]*"/src/render/admin.jl")

time_initing=0.0
time_transforming=0.0
time_saving=0.0
time_waiting=0.0

# keep boss informed
sock = connect(ARGS[7],parse(Int,ARGS[8]))

type NDException <: Exception end

const write = "manager tells peon for input tile "*ARGS[4]*" to write output tile"
const send = "manager tells peon for input tile "*ARGS[4]*" to send output tile"
const receive = "manager tells peon for input tile "*ARGS[4]*" to receive output tile"

# 2 -> sizeof(UInt16), 20e3 -> .tif metadata size, 15 -> max # possible concurrent saves, need to generalize
enough_free(path) = parse(Int,split(readall(`df $path`))[11])*1024 > 15*((prod(shape_leaf_px)*2 + 20e3))

function depth_first_traverse(bbox, out_tile_path, sub_tile_str,
        sub_transform_nm, orientation, in_subtile_aabb)
  cboxes = AABBBinarySubdivision(bbox)

  global out_tiles_ws, out_tiles_jl, time_transforming, time_saving, time_waiting

  for i=1:8
    AABBHit(cboxes[i], in_subtile_aabb) || continue
    out_tile_path_next = joinpath(out_tile_path,string(i))

    if !isleaf(cboxes[i])
      depth_first_traverse(cboxes[i], out_tile_path_next, sub_tile_str,
           sub_transform_nm, orientation, in_subtile_aabb)
    else
      info("processing output tile ",out_tile_path_next)

      t0=time()
      const origin_nm = AABBGetJ(cboxes[i])[2]
      const transform = (sub_transform_nm .- origin_nm) ./ (voxelsize_used_um*um2nm)

      if !haskey(out_tiles_ws,out_tile_path_next)
        out_tiles_ws[out_tile_path_next] = ndalloc(shape_leaf_px, data_type)
        out_tiles_jl[out_tile_path_next] = pointer_to_array(convert(Ptr{UInt16},
              nddata(out_tiles_ws[out_tile_path_next])), tuple(shape_leaf_px...))
        ndfill(out_tiles_ws[out_tile_path_next], 0x0000)
        tmp = map(x->AABBHit(cboxes[i], x), in_subtiles_aabb)
        merge_count[out_tile_path_next]=UInt8[ sum(tmp), 0 ]
      end

      if !isnan(thisgpu)
        #BarycentricGPUdestination(resampler, nddata(out_tiles_ws[out_tile_path_next]))
        #BarycentricGPUresample(resampler, convert(Array{Float32}, transform))
        #BarycentricGPUresult(resampler, nddata(out_tiles_ws[out_tile_path_next]))
      elseif has_avx2
        BarycentricAVXdestination(resampler, nddata(out_tiles_ws[out_tile_path_next]))
        BarycentricAVXresample(resampler, convert(Array{Float32}, transform), orientation, interpolation)
        BarycentricAVXresult(resampler, nddata(out_tiles_ws[out_tile_path_next]))
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
          save_out_tile(shared_scratch, out_tile_path_next, string(ARGS[5],'.',channel-1,'.',file_format),
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
            out_tiles_jl[out_tile_path_next][:] = max(out_tiles_jl[out_tile_path_next]::Array{UInt16,3},
                deserialize(sock)::Array{UInt16,3})
            save_out_tile(shared_scratch, out_tile_path_next, string(ARGS[5],'.',channel-1,'.',file_format),
                out_tiles_ws[out_tile_path_next])
            println(sock,"peon for input tile ",ARGS[4]," saved output tile ",out_tile_path_next)
            info("peon transfered output tile ",out_tile_path_next," from RAM to shared_scratch")
          elseif startswith(tmp,write)
            if enough_free(local_scratch)
              save_out_tile(local_scratch, out_tile_path_next,
                  string(in_tile_idx,'.',sub_tile_str,'.',channel-1,'.',file_format),
                  out_tiles_ws[out_tile_path_next])
              println(sock,"peon for input tile ",ARGS[4],
                  " wrote output tile ",out_tile_path_next," to local_scratch")
            else
              save_out_tile(shared_scratch, out_tile_path_next,
                  string(ARGS[5],'.',in_tile_idx,'.',sub_tile_str,'.',channel-1,'.',file_format),
                  out_tiles_ws[out_tile_path_next])
              msg = "peon for input tile "*string(ARGS[4])*
                  " wrote output tile "*out_tile_path_next*" to shared_scratch"
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
    shape_intile = ndshapeJ(tmp)[1:3]
    global data_type = ndtype(tmp)
    in_tile_ws = ndalloc(shape_intile, data_type)
    in_tile_jl = pointer_to_array(convert(Ptr{UInt16},nddata(in_tile_ws)), tuple(shape_intile...))
    in_subtile_ws = ndinit()
    ndcast(in_subtile_ws, data_type)
    tmp=split(bytestring(TilePath(tile)),"/")
    push!(tmp, string(tmp[end],'-',file_infix,'.',channel-1,'.',file_format))
    ndioClose(ndioRead(ndioOpen("/"*joinpath(tmp...), C_NULL, "r"), in_tile_ws))
    info("reading input tile ",in_tile_idx," took ",round(Int,time()-t1)," sec")
    filename = "/"*joinpath(tmp...)
    for ratio in octree_compression_ratios
      spawn(`$(ENV["RENDER_PATH"])/src/mj2/compressfiles/run_compressbrain_cluster.sh /usr/local/matlab-2014b $ratio $filename $(dirname(filename)) $(splitext(basename(filename))[1]) 0`)
    end

  catch
    error("in peon/ndalloc")
  end

  global in_subtiles_aabb = calc_in_subtiles_aabb(tile,xlims,ylims,zlims,transform_nm)

  # for each input subtile, recursively traverse the output tiles
  shape_leaf_ptr = pointer(convert(Array{Cuint,1},shape_leaf_px))
  for ix=1:length(xlims)-1, iy=1:length(ylims)-1, iz=1:length(zlims)-1
    info("processing transform ",xlims[ix:ix+1],"-",ylims[iy:iy+1],"-",zlims[iz:iz+1],
          " for input tile ",in_tile_idx)
    t1=time()
    in_subtile_jl = in_tile_jl[1+(xlims[ix]:xlims[ix+1]),1+(ylims[iy]:ylims[iy+1]),1+(zlims[iz]:zlims[iz+1])]
    map((i,x)->ndShapeSet(in_subtile_ws, i, x), 1:3, size(in_subtile_jl))
    ndref(in_subtile_ws, pointer(in_subtile_jl), convert(Cint,0))
    try
      global resampler = Ptr{Void}[0]
      if !isnan(thisgpu)
        #cudaSetDevice(thisgpu)
        #info("initializing GPU ",thisgpu,", ",signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2)," GB free")
        #BarycentricGPUinit(resampler, ndshape(in_subtile_ws), shape_leaf_ptr , 3)
        #BarycentricGPUsource(resampler, nddata(in_subtile_ws))
        #info("initialized GPU ",thisgpu,", ",signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2)," GB free")
      elseif has_avx2
        BarycentricAVXinit(resampler, ndshape(in_subtile_ws), shape_leaf_ptr, 3)
        BarycentricAVXsource(resampler, nddata(in_subtile_ws))
      else
        BarycentricCPUinit(resampler, ndshape(in_subtile_ws), shape_leaf_ptr, 3)
        BarycentricCPUsource(resampler, nddata(in_subtile_ws))
      end
    catch
      error("BarycentricInit error:  GPU $thisgpu, input tile $in_tile_idx")
    end
    time_initing+=(time()-t1)

    depth_first_traverse(TileBaseAABB(tiles), "", string(ix)*"x"*string(iy)*"x"*string(iz),
        transform_nm[:,subtile_corner_indices(ix,iy,iz)],
        isodd(ix+iy+iz) ? 90 : 0,
        in_subtiles_aabb[ix,iy,iz])
  end

  ndfree(in_subtile_ws)
  ndfree(in_tile_ws)

  try
    #TileFree(tile)
    TileBaseClose(tiles)
  catch
    error("peon/TileBaseClose")
  end

  try
    if !isnan(thisgpu)
      #info("releasing GPU ",thisgpu,", ",signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2)," GB free")
      #BarycentricGPUrelease(resampler)
      #info("released GPU ",thisgpu,", ",signif(cudaMemGetInfo()[1]/1024/1024/1024,4,2)," GB free")
    elseif has_avx2
      BarycentricAVXrelease(resampler)
    else
      BarycentricCPUrelease(resampler)
    end
  catch
    error("BarycentricRelease error:  GPU $thisgpu, input tile $in_tile_idx")
  end

  info("initializing input tile ",in_tile_idx, " took ",round(Int,time_initing)," sec")
  info("transforming input tile ",in_tile_idx," took ",round(Int,time_transforming)," sec")
  info("saving output tiles for input tile ",in_tile_idx," took ",round(Int,time_saving)," sec")
  info("waiting for manager for input tile ",in_tile_idx," took ",round(Int,time_waiting)," sec")
  info("input tile ",in_tile_idx," took ",round(Int,time()-t0)," sec overall")

  map(AABBFree,in_subtiles_aabb)
end

const local_scratch="/scratch/"*readchomp(`whoami`)
const channel = parse(Int,ARGS[3])
const solo_out_tiles = eval(parse(ARGS[6]))
const thisgpu = ARGS[2]=="NaN" ? NaN : parse(Int,ARGS[2])
const in_tile_idx = parse(Int,ARGS[4])
idx = 9
const xlims = map(x->parse(Int,x), ARGS[idx+(1:parse(Int,ARGS[idx]))])
idx += length(xlims)+1
const ylims = map(x->parse(Int,x), ARGS[idx+(1:parse(Int,ARGS[idx]))])
idx += length(ylims)+1
const zlims = map(x->parse(Int,x), ARGS[idx+(1:parse(Int,ARGS[idx]))])
idx += length(zlims)+1
const dims = -1+map(x->parse(Int,x), ARGS[idx:idx+2])
idx += length(dims)
const transform_nm = reshape(map(x->parse(Int,x), ARGS[idx:end]),3,length(xlims)*length(ylims)*length(zlims))

const out_tiles_ws = Dict{ASCIIString,Ptr{Void}}()
const out_tiles_jl = Dict{ASCIIString,Array{UInt16,3}}()
const merge_count = Dict{ASCIIString,Array{UInt8,1}}()

@assert all(diff(diff(xlims)).==0) "xlims not equally spaced for input tile $in_tile_idx"
@assert all(diff(diff(ylims)).==0) "ylims not equally spaced for input tile $in_tile_idx"
@assert all(diff(zlims).>0) "zlims not in ascending order for input tile $in_tile_idx"
@assert xlims[1]>=0 && xlims[end]<=dims[1] "xlims out of range for input tile $in_tile_idx"
@assert ylims[1]>=0 && ylims[end]<=dims[2] "ylims out of range for input tile $in_tile_idx"
@assert zlims[1]>=0 && zlims[end]<=dims[3] "zlims out of range for input tile $in_tile_idx"

if !dry_run
  process_tile()

  for (k,v) in merge_count
    info((k,v))
    v[1]>1 && v[1]!=v[2] && warn("not all input subtiles processed for output tile ",k," : ",v)
  end

  map(ndfree,values(out_tiles_ws))
end

#closelibs()

# keep boss informed
println(sock,"peon for input tile ",ARGS[4]," is finished")
close(sock)
