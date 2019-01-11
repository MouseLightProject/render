# spawned by manager
# processes all leaf output tiles from a given input tile
# for outputs with more than one input, sends results back to manager vi tcp
#    (or saves to local_scratch if needed), otherwise saves to shared_scratch
# saves stdout/err to <destination>/squatter[0-9]*.log

# julia peon.jl parameters.jl in_tile origin_str solo_out_tiles hostname port nxlims xlims nylims ylims nzlims zlims dims[1:3] transform[1-3*2*(n+1)^2]

import ImageMagick
using Images, HDF5, Sockets, Morton

include(ARGS[1])
include("$destination/calculated_parameters.jl")
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

const local_scratch="/scratch/"*readchomp(`whoami`)
const origin_str = ARGS[3]
const in_tile_idx = parse(Int,ARGS[2])
const solo_out_tiles = eval(Meta.parse(ARGS[4]))
idx = 7
const nxlims = parse(Int,ARGS[idx])
const xlims = [parse(Int,x) for x in ARGS[idx.+(1:nxlims)]]
idx += nxlims+1
const nylims = parse(Int,ARGS[idx])
const ylims = [parse(Int,x) for x in ARGS[idx.+(1:nylims)]]
idx += nylims+1
const nzlims = parse(Int,ARGS[idx])
const zlims = [parse(Int,x) for x in ARGS[idx.+(1:nzlims)]]
idx += nzlims+1
const dims = -1 .+ [parse(Int,x) for x in ARGS[idx:idx+2]]
idx += length(dims)
const transform_nm = reshape([parse(Int,x) for x in ARGS[idx:end]], 3, nxlims*nylims*nzlims)

@assert all(diff(diff(xlims)).==0) "xlims not equally spaced for input tile $in_tile_idx"
@assert all(diff(diff(ylims)).==0) "ylims not equally spaced for input tile $in_tile_idx"
@assert all(diff(zlims).>0) "zlims not in ascending order for input tile $in_tile_idx"
@assert xlims[1]>=0 && xlims[end]<=dims[1] "xlims out of range for input tile $in_tile_idx"
@assert ylims[1]>=0 && ylims[end]<=dims[2] "ylims out of range for input tile $in_tile_idx"
@assert zlims[1]>=0 && zlims[end]<=dims[3] "zlims out of range for input tile $in_tile_idx"

# keep boss informed
sock = connect(ARGS[5],parse(Int,ARGS[6]))

time_initing = 0.0
time_transforming = 0.0
time_saving = 0.0
time_waiting = 0.0

const write_msg = string("manager tells peon for input tile ",in_tile_idx," to write output tile")
const send_msg = string("manager tells peon for input tile ",in_tile_idx," to send output tile")
const receive_msg = string("manager tells peon for input tile ",in_tile_idx," to receive output tile")
const merge_msg = string("manager tells peon for input tile ",in_tile_idx," to merge output tile")

const out_tiles = Dict{String,Array{UInt16,4}}()
const merge_count = Dict{String,Array{UInt8,1}}()

# 2 -> sizeof(UInt16), 20e3 -> .tif metadata size, 15 -> max # possible concurrent saves, need to generalize
enough_free(path) = parse(Int,split(read(`df $path`, String))[11])*1024 > 15*((prod(shape_leaf_px)*2 + 20e3))

function depth_first_traverse_over_output_tiles(bbox, out_tile_path, sub_tile_str,
        sub_transform_nm, orientation, in_subtile_aabb)
  cboxes = AABBBinarySubdivision(bbox)

  global out_tiles, time_transforming, time_saving, time_waiting

  for imorton = 1:8
    AABBHit(cboxes[imorton], in_subtile_aabb) || continue
    out_tile_path_next = joinpath(out_tile_path,string(imorton))

    if !isleaf(cboxes[imorton])
      depth_first_traverse_over_output_tiles(cboxes[imorton], out_tile_path_next, sub_tile_str,
           sub_transform_nm, orientation, in_subtile_aabb)
    else
      @info string("PEON: processing output tile ",out_tile_path_next)

      t0=time()
      origin_nm = AABBGet(cboxes[imorton])[1]
      transform = (sub_transform_nm .- origin_nm) ./ (voxelsize_used_um*um2nm)
      transform32 = convert(Array{Float32}, transform)

      if !haskey(out_tiles,out_tile_path_next)
        out_tiles[out_tile_path_next] = zeros(UInt16, shape_leaf_px..., nchannels)
        overlapped_insubtiles::Array{Bool,3} = map(x->AABBHit(cboxes[imorton], x), in_subtiles_aabb)
        merge_count[out_tile_path_next]=UInt8[ sum(overlapped_insubtiles), 0 ]
      end

      if has_avx2 && use_avx
        BarycentricAVXdestination(resampler, out_tiles[out_tile_path_next])
        BarycentricAVXresample(resampler, transform32, orientation, interpolation)
        BarycentricAVXresult(resampler, out_tiles[out_tile_path_next])
      else
        BarycentricCPUdestination(resampler, out_tiles[out_tile_path_next])
        BarycentricCPUresample(resampler, transform32, orientation, interpolation)
        BarycentricCPUresult(resampler, out_tiles[out_tile_path_next])
      end
      time_transforming+=(time()-t0)

      merge_count[out_tile_path_next][2]+=1
      if merge_count[out_tile_path_next][2]==merge_count[out_tile_path_next][1]
        t0=time()
        if out_tile_path_next in solo_out_tiles
          save_tile(shared_scratch, out_tile_path_next, origin_str, file_format_save,
              out_tiles[out_tile_path_next])
          @info string("PEON: transfered output tile ",out_tile_path_next,
                       " from RAM to shared_scratch")
        else
          msg_to_manager =
                string("peon for input tile ",in_tile_idx,
                       " has output tile ",out_tile_path_next," ready")
          println(sock, msg_to_manager)
          @info string("PEON: ",msg_to_manager)
          t1=time()
          local msg_from_manager::String
          while true
            msg_from_manager = chomp(readline(sock,keep=true))
            length(msg_from_manager)==0 || break
          end
          time_waiting+=(time()-t1)
          @info string("PEON<MANAGER: ",msg_from_manager)
          if startswith(msg_from_manager, send_msg)
            msg = string("peon for input tile ",in_tile_idx,
                         " will send output tile ",out_tile_path_next)
            println(sock,msg)
            @info string("PEON: ",msg)
            serialize(sock, out_tiles[out_tile_path_next])
          elseif startswith(msg_from_manager, receive_msg)
            out_tile_from_manager::Array{UInt16,4} = deserialize(sock)
            local_out_tile = out_tiles[out_tile_path_next]
            for i4=1:nchannels, i3=1:shape_leaf_px[3], i2=1:shape_leaf_px[2], i1=1:shape_leaf_px[1]
              @inbounds local_out_tile[i1,i2,i3,i4] =
                    max(local_out_tile[i1,i2,i3,i4], out_tile_from_manager[i1,i2,i3,i4])
            end
            out_tile_from_manager = Array{UInt16}(undef, 0,0,0,0)
            GC.gc()
            save_tile(shared_scratch, out_tile_path_next, origin_str, file_format_save,
                  out_tiles[out_tile_path_next])
            msg = string("peon for input tile ",in_tile_idx,
                         " saved output tile ",out_tile_path_next)
            println(sock,msg)
            @info string("PEON: ",msg)
          elseif startswith(msg_from_manager, write_msg) || startswith(msg_from_manager, merge_msg)
            if enough_free(local_scratch)
              save_tile(local_scratch, out_tile_path_next,
                    string(in_tile_idx,'.',sub_tile_str), file_format_save,
                    out_tiles[out_tile_path_next])
              msg = string("peon for input tile ",in_tile_idx,
                    " wrote output tile ",out_tile_path_next," to local_scratch")
              println(sock,msg)
              @info string("PEON: ",msg)
            else
              save_tile(shared_scratch, out_tile_path_next,
                    string(origin_str,'.',in_tile_idx,'.',sub_tile_str), file_format_save,
                    out_tiles[out_tile_path_next])
              msg = string("peon for input tile ",in_tile_idx,
                    " wrote output tile ",out_tile_path_next," to shared_scratch")
              println(sock,msg)
              @warn(msg)
            end
            if startswith(msg_from_manager, merge_msg)
              merge_output_tiles(local_scratch, shared_scratch,
                    origin_str, file_format_save, out_tile_path_next, false, false, true)
              msg = string("peon for input tile ",in_tile_idx,
                           " merged output tile ",out_tile_path_next,
                           " from local_scratch to shared_scratch")
              #println(sock,msg)  # not captured by manager
              @info string("PEON: ",msg)
            end
          end
        end
        delete!(out_tiles,out_tile_path_next)
        time_saving+=(time()-t0)
      end
    end
  end
end

function process_input_tile()
  t0=time()
  global time_initing

  local tiles
  tiles = TileBaseOpen(source)
  global tile = TileBaseIndex(tiles, in_tile_idx)

  @info string("PEON: processing input tile $in_tile_idx: ",TilePath(tile))

  local in_tile::Array{UInt16,4}, in_subtile::Array{UInt16,4}
  t1=time()
  shape_intile = TileShape(tile)
  tile_path=TilePath(tile)
  tile_fullpath=joinpath(TileBasePath(tiles)*tile_path, string(basename(tile_path),'-',file_infix))
  in_tile = load_tile(tile_fullpath, file_format_load, shape_intile)
  @info string("PEON: reading input tile ",in_tile_idx," took ",round(Int,time()-t1)," sec")

  global in_subtiles_aabb = calc_in_subtiles_aabb(tile,xlims,ylims,zlims,transform_nm)

  # for each input subtile, recursively traverse the output tiles
  shape_leaf_nchannels = convert(Array{Cuint,1},vcat(shape_leaf_px,nchannels))
  for m=1:max(nxlims,nylims,nzlims)^3
    ix,iy,iz = morton3cartesian(m)
    (ix>nxlims-1 || iy>nylims-1 || iz>nzlims-1) && continue

    @info string("PEON: processing transform ",xlims[ix:ix+1],"-",ylims[iy:iy+1],"-",zlims[iz:iz+1],
          " for input tile ",in_tile_idx)
    t1=time()
    in_subtile = in_tile[1 .+ (xlims[ix]:xlims[ix+1]),
                         1 .+ (ylims[iy]:ylims[iy+1]),
                         1 .+ (zlims[iz]:zlims[iz+1]), :]
    shape_in_subtile = convert(Array{Cuint,1},[size(in_subtile)...])
    global resampler = Ptr{Cvoid}[0]
    if has_avx2 && use_avx
      BarycentricAVXinit(resampler, shape_in_subtile, shape_leaf_nchannels, 4)
      BarycentricAVXsource(resampler, in_subtile)
    else
      BarycentricCPUinit(resampler, shape_in_subtile, shape_leaf_nchannels, 4)
      BarycentricCPUsource(resampler, in_subtile)
    end
@info in_subtile[1]  ### hack or the image is garbled.  wtf
    time_initing+=(time()-t1)

    depth_first_traverse_over_output_tiles(TileBaseAABB(tiles), "", string(ix,'x',iy,'x',iz),
        transform_nm[:,subtile_corner_indices(ix,iy,iz)],
        isodd(ix+iy+iz) ? 90 : 0,
        in_subtiles_aabb[ix,iy,iz])
  end

  if has_avx2 && use_avx
    BarycentricAVXrelease(resampler)
  else
    BarycentricCPUrelease(resampler)
  end

  @info string("PEON: initializing input tile ",in_tile_idx,
               " took ",round(Int,time_initing)," sec")
  @info string("PEON: transforming input tile ",in_tile_idx,
               " took ",round(Int,time_transforming)," sec")
  @info string("PEON: saving output tiles for input tile ",in_tile_idx,
               " took ",round(Int,time_saving)," sec")
  @info string("PEON: waiting for manager for input tile ",in_tile_idx,
               " took ",round(Int,time_waiting)," sec")
  @info string("PEON: input tile ",in_tile_idx,
               " took ",round(Int,time()-t0)," sec overall")
end

if !dry_run
  process_input_tile()

  for (k,v) in merge_count
    v[1]>1 && v[1]!=v[2] && @warn string("not all input subtiles processed for output tile ",k," : ",v)
  end
  #@info string("PEON: ",merge_count)  ### causes seg faults
end

#closelibs()

# keep boss informed
msg = string("peon for input tile ",in_tile_idx," is finished")
println(sock,msg)
@info string("PEON: ",msg)
close(sock)
