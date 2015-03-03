const um2nm=1e3

# interface to CUDA

# map((x)->(cudaSetDevice(x); [cudaMemGetInfo()...]./1024^3), 0:cudaGetDeviceCount()-1)

const libcudart = ENV["LD_LIBRARY_PATH"]*"/libcudart.so"

function cudaGetDeviceCount()
  count = Cint[0]
  ccall((:cudaGetDeviceCount, libcudart), Cint, (Ptr{Cint},), count)==0 || throw(Exception)
  count[1]
end

function cudaMemGetInfo()
  free = Csize_t[0]
  total = Csize_t[0]
  ccall((:cudaMemGetInfo, libcudart), Cint, (Ptr{Csize_t},Ptr{Csize_t}), free,total)==0 || throw(Exception)
  free[1], total[1]
end

function cudaGetDevice()
  dev = Cint[0]
  ccall((:cudaGetDevice, libcudart), Cint, (Ptr{Cint},), dev)==0 || throw(Exception)
  dev[1]
end

function cudaSetDevice(dev)
  ccall((:cudaSetDevice, libcudart), Cint, (Cint,), dev)==0 || throw(Exception)
  nothing
end

cudaDeviceReset() =  ccall((:cudaDeviceReset, libcudart), Cint, (), )==0 || throw(Exception)

try
  global ngpus = cudaGetDeviceCount()
catch
  global ngpus = 0
end

if ngpus == 7
  envpath="/env/570"
elseif ngpus == 4
  envpath="/env/k20"
else
  envpath="/env/cpu"
end

# interface to tilebase

const libtilebase = ENV["RENDER_PATH"]*envpath*"/lib/libtilebase.so"

TileBaseOpen(source) = ccall((:TileBaseOpen, libtilebase), Ptr{Void}, (Ptr{Uint8},Ptr{Uint8}), source, C_NULL)
TileBaseClose(tiles) = ccall((:TileBaseClose, libtilebase), Void, (Ptr{Void},), tiles)
TileBaseAABB(tiles) = ccall((:TileBaseAABB, libtilebase), Ptr{Void}, (Ptr{Void},), tiles)
TileBaseCount(tiles) = ccall((:TileBaseCount, libtilebase), Csize_t, (Ptr{Void},), tiles)
TileBaseIndex(tiles, idx) = ccall((:TileBaseIndex, libtilebase), Ptr{Void}, (Ptr{Void},Cuint), tiles,idx-1)

TileAABB(tile) = ccall((:TileAABB, libtilebase), Ptr{Void}, (Ptr{Void},), tile)
TileShape(tile) = ccall((:TileShape, libtilebase), Ptr{Void}, (Ptr{Void},), tile)
TileFile(tile) = ccall((:TileFile, libtilebase), Ptr{Void}, (Ptr{Void},), tile)
TilePath(tile) = ccall((:TilePath, libtilebase), Ptr{Uint8}, (Ptr{Void},), tile)
TileFree(tile) = ccall((:TileFree, libtilebase), Ptr{Void}, (Ptr{Void},), tile)

AABBMake(ndim) = ccall((:AABBMake, libtilebase), Ptr{Void}, (Ptr{Csize_t},), ndim)
AABBFree(bbox) = ccall((:AABBFree, libtilebase), Void, (Ptr{Void},), bbox)
AABBGet(bbox,ndim,ori,shape) = ccall((:AABBGet, libtilebase),
    Ptr{Void}, (Ptr{Void},Ptr{Csize_t},Ptr{Ptr{Int}},Ptr{Ptr{Int}}), bbox,ndim,ori,shape)
AABBSet(bbox,ndim,ori,shape) = ccall((:AABBSet, libtilebase),
    Ptr{Void}, (Ptr{Void},Csize_t,Ptr{Int},Ptr{Int}), bbox,ndim,ori,shape)
AABBVolume(bbox) = ccall((:AABBVolume, libtilebase), Cdouble, (Ptr{Void},), bbox)
AABBNDim(bbox) = ccall((:AABBNDim, libtilebase), Csize_t, (Ptr{Void},), bbox)
AABBHit(bbox1,bbox2) = ccall((:AABBHit, libtilebase), Cint, (Ptr{Void},Ptr{Void}), bbox1,bbox2)
AABBUnionIP(bbox1,bbox2) =
    ccall((:AABBUnionIP, libtilebase), Ptr{Void}, (Ptr{Void},Ptr{Void}), bbox1,bbox2)
AABBIntersectIP(bbox1,bbox2) =
    ccall((:AABBIntersectIP, libtilebase), Ptr{Void}, (Ptr{Void},Ptr{Void}), bbox1,bbox2)
AABBCopy(bbox1,bbox2) =
    ccall((:AABBCopy, libtilebase), Ptr{Void}, (Ptr{Void},Ptr{Void}), bbox1,bbox2)

function AABBBinarySubdivision(bbox)
  cboxes = fill(C_NULL, 8)
  ccall((:AABBBinarySubdivision, libtilebase), Ptr{Void}, (Ptr{Void},Cuint,Ptr{Void}), cboxes,8,bbox)
  cboxes
end

function AABBGetJ(bbox)
  ndim = Csize_t[0]
  origin = Ptr{Int}[0]
  shape = Ptr{Int}[0]
  ccall((:AABBGet, libtilebase),
    Ptr{Void}, (Ptr{Void},Ptr{Csize_t},Ptr{Ptr{Int}},Ptr{Ptr{Int}}), bbox,ndim,origin,shape)
  ndim[1], pointer_to_array(origin[1],ndim[1]), pointer_to_array(shape[1],ndim[1])
end

# interface to nd

const libnd = ENV["RENDER_PATH"]*envpath*"/lib/libnd.so"

ndinit() = ccall((:ndinit, libnd), Ptr{Void}, ())
ndheap(nd_t) = ccall((:ndheap, libnd), Ptr{Void}, (Ptr{Void},), nd_t)
ndfree(nd_t) = ccall((:ndheap, libnd), Void, (Ptr{Void},), nd_t)
nddata(nd_t) = ccall((:nddata, libnd), Ptr{Void}, (Ptr{Void},), nd_t)
ndtype(nd_t) = ccall((:ndtype, libnd), Cint, (Ptr{Void},), nd_t)
ndkind(nd_t) = ccall((:ndkind, libnd), Cint, (Ptr{Void},), nd_t)
ndndim(nd_t) = ccall((:ndndim, libnd), Cuint, (Ptr{Void},), nd_t)
ndcopy_ip(nd_t_dst, nd_t_src) =
    ccall((:ndcopy_ip, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void}), nd_t_dst, nd_t_src)
ndcast(nd_t,t) = ccall((:ndcast, libnd), Ptr{Void}, (Ptr{Void},Cint), nd_t,t)
ndfill(nd_t,c) = ccall((:ndfill, libnd), Ptr{Void}, (Ptr{Void},Uint64), nd_t,c)
ndref(nd_t,data,kind) = ccall((:ndref, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void},Cint), nd_t,data,kind)
ndnbytes(nd_t) = ccall((:ndnbytes, libnd), Csize_t, (Ptr{Void},), nd_t)
ndShapeSet(nd_t, idim, val) =
    ccall((:ndShapeSet, libnd), Ptr{Void}, (Ptr{Void},Cuint,Csize_t), nd_t, idim-1, val)
ndioOpen(filename,format,mode) =
    ccall((:ndioOpen, libnd), Ptr{Void}, (Ptr{Uint8},Ptr{Void},Ptr{Uint8}), filename, format, mode)
ndioRead(file,dst) = ccall((:ndioRead, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void}), file, dst)
ndioReadSubarray(file,dst,origin,shape) =
    ccall((:ndioReadSubarray, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void},Ptr{Csize_t},Ptr{Csize_t}),
    file, dst, origin, shape)
ndioWrite(file,src) = ccall((:ndioWrite, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void}), file, src)
ndioClose(file) = ccall((:ndioClose, libnd), Void, (Ptr{Void},), file)
ndioShape(file) = ccall((:ndioShape, libnd), Ptr{Void}, (Ptr{Void},), file)

retain_for_gc = Any[]

for f in ("ndshape", "ndstrides")
  @eval function $(symbol(f))(nd_t)
    push!(retain_for_gc, convert(Array{Cuint}, pointer_to_array(  # hack: size_t -> Cuint
        ccall(($f, libnd), Ptr{Csize_t}, (Ptr{Void},), nd_t)
        ,ndndim(nd_t))) )
    pointer(retain_for_gc[end])
  end
  @eval function $(symbol(f*"J"))(nd_t)  # memory leak?
    pointer_to_array(
        ccall(($f, libnd), Ptr{Csize_t}, (Ptr{Void},), nd_t)
        ,ndndim(nd_t))
  end
end

# interface to mltk-bary

dlopen("libcudart.so",RTLD_LAZY|RTLD_DEEPBIND|RTLD_GLOBAL)
const libengine = ENV["RENDER_PATH"]*envpath*"/build/mltk-bary/libengine.so"

type BarycentricException <: Exception end

BarycentricCPUinit(r,src_shape,dst_shape,ndims) =  ccall((:BarycentricCPUinit, libengine),
      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricGPUinit(r,src_shape,dst_shape,ndims) =  ccall((:BarycentricGPUinit, libengine),
      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricCPUresample(r,cube) =  ccall((:BarycentricCPUresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat}),
      r,cube) !=1 && throw(BarycentricException())

BarycentricGPUresample(r,cube) =  ccall((:BarycentricGPUresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat}),
      r,cube) !=1 && throw(BarycentricException())

BarycentricCPUrelease(r) = ccall((:BarycentricCPUrelease, libengine), Void, (Ptr{Ptr{Void}},), r)
BarycentricGPUrelease(r) = ccall((:BarycentricGPUrelease, libengine), Void, (Ptr{Ptr{Void}},), r)

for f = ("source", "destination", "result")
  @eval $(symbol("BarycentricCPU"*f))(r,src) =
      ccall(($("BarycentricCPU"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{Uint16}),
          r,src) !=1 && throw(BarycentricException())
  @eval $(symbol("BarycentricGPU"*f))(r,src) =
      ccall(($("BarycentricGPU"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{Uint16}),
          r,src) !=1 && throw(BarycentricException())
end

# port some of tilebase/app/render

function isleaf(bbox)
  c = AABBVolume(bbox) / (prod(voxelsize_used_um)*um2nm^3)
  c < countof_leaf
end

# port some of julia 4.0 base since we're using julia 3.x

function startswith(a::String, b::String)
    i = start(a)
    j = start(b)
    while !done(a,i) && !done(b,i)
        c, i = next(a,i)
        d, j = next(b,j)
        if c != d return false end
    end
    done(b,i)
end

# used by both director and deputy

function ndalloc(tileshape, tiletype, heap=true)
  tmp_ws = ndinit()
  ndShapeSet(tmp_ws, 1, tileshape[1])
  ndShapeSet(tmp_ws, 2, tileshape[2])
  ndShapeSet(tmp_ws, 3, tileshape[3])
  ndcast(tmp_ws, tiletype)
  heap || return tmp_ws
  tile_ws=ndheap(tmp_ws)
  ndfree(tmp_ws)
  tile_ws
end

# 2 -> sizeof(Uint16), 20e3 -> .tif metadata size, 8 -> max # possible concurrent saves, need to generalize
enough_free(path) = int(split(readall(`df $path`))[11])*1024 > 8*(prod(shape_leaf_px)*2 + 20e3)

:shape_leaf_px in names(Main) && (save_ws = ndalloc(shape_leaf_px, tile_type, false))

function save_out_tile(filesystem, path, name, data::Array{Uint16,3})
  ndref(save_ws, pointer(data), convert(Cint,0))   # 0==nd_heap;  need to generalize
  save_out_tile(filesystem, path, name, save_ws)
end

function save_out_tile(filesystem, path, name, data::Ptr{Void})
  try
    enough_free(filesystem) || return false
    filepath = joinpath(filesystem,path)
    filename = joinpath(filepath,name)
    try;  mkpath(filepath);  end
    ndioClose(ndioWrite(ndioOpen(filename, C_NULL, "w"), data))
    return true
  catch
    error("in save_out_tile")
  end
end

function merge_guts(in_tiles, destination, delete,
      merge1_ws::Ptr{Void}, merge2_ws::Ptr{Void}, merge1::Array{Uint16,3}, merge2::Array{Uint16,3})
  if length(in_tiles)==1
    t0=time()
    info("copying from ",in_tiles[1])
    info("  to ",destination)
    cp(in_tiles[1],destination)
    delete && (info("  deleting ",in_tiles[1]); rm(in_tiles[1]))
    time_single_file=(time()-t0)
    return time_single_file, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
  else
    t0=time()
    info("merging:")
    t1=time()
    ndfill(merge1_ws, 0x0000)
    time_clear_files=(time()-t1)
    for in_tile in in_tiles
      info("  reading ",in_tile)
      t1=time()
      ndioClose(ndioRead(ndioOpen( in_tile, C_NULL, "r" ),merge2_ws))
      time_read_files=(time()-t1)
      t1=time()
      merge1[:,:,:] = max(merge1,merge2)
      time_max_files=(time()-t1)
      t1=time()
      delete && (info("  deleting ",in_tile); rm(in_tile))
      time_delete_files=(time()-t1)
    end
    info("  copying to ",destination)
    t1=time()
    ndioClose(ndioWrite(ndioOpen( destination, C_NULL, "w" ),merge1_ws))
    time_write_files=(time()-t1)
    time_many_files=(time()-t0)
    return 0.0, time_many_files, time_clear_files, time_read_files, time_max_files, time_delete_files, time_write_files
  end
end

merge_across_filesystems(source::ASCIIString, destination, prefix, chantype, out_tile_path, recurse::Bool, delete::Bool) =
      merge_across_filesystems([source], destination, prefix, chantype, out_tile_path, recurse, delete)

function merge_across_filesystems(sources::Array{ASCIIString,1}, destination, prefix, chantype, out_tile_path, recurse::Bool, delete::Bool)
  global time_single_file, time_many_files, time_clear_files, time_read_files, time_max_files, time_delete_files, time_write_files

  dirs=ASCIIString[]
  in_tiles=ASCIIString[]
  for source in sources
    isdir(joinpath(source,out_tile_path)) || continue
    listing = readdir(joinpath(source,out_tile_path))
    idx = map(x->isdir(joinpath(source,out_tile_path,x)), listing)
    push!(dirs, listing[idx]...)
    push!(in_tiles, [joinpath(source,out_tile_path,x) for x in listing[!idx & map(x->endswith(x,chantype), listing)]]...)
  end

  recurse && for dir in unique(dirs)
    merge_across_filesystems(sources, destination, prefix, chantype, joinpath(out_tile_path,dir), recurse, delete)
  end
  length(in_tiles)==0 && return

  enough_free(dirname(destination)) || throw(Exception)
  try;  mkpath(joinpath(destination,out_tile_path));  end

  tmp = merge_guts(in_tiles, joinpath(destination, out_tile_path, prefix * chantype), delete, merge1_ws, merge2_ws, merge1, merge2)

  time_single_file += tmp[1]
  time_many_files += tmp[2]
  time_clear_files += tmp[3]
  time_read_files += tmp[4]
  time_max_files += tmp[5]
  time_delete_files += tmp[6]
  time_write_files += tmp[7]
end

merge_output_tiles(source, destination, prefix, chantype, out_tile_path, recurse::Bool, delete::Bool) =
      merge_output_tiles(()->merge_across_filesystems(source, destination, prefix, chantype, out_tile_path, recurse, delete))

function merge_output_tiles(callback::Function)
  global time_single_file=0.0, time_many_files=0.0, time_ram_file=0.0
  global time_clear_files=0.0, time_read_files=0.0, time_max_files=0.0, time_delete_files=0.0, time_write_files=0.0

  global merge1_ws, merge2_ws, merge1, merge2
  merge1_ws = ndalloc(shape_leaf_px, tile_type)
  merge2_ws = ndalloc(shape_leaf_px, tile_type)
  merge1 = pointer_to_array(convert(Ptr{Uint16},nddata(merge1_ws)), tuple(shape_leaf_px...))
  merge2 = pointer_to_array(convert(Ptr{Uint16},nddata(merge2_ws)), tuple(shape_leaf_px...))

  callback()

  ndfree(merge1_ws)
  ndfree(merge2_ws)

  info("copying single files took ",string(iround(time_single_file))," sec")
  info("merging multiple files took ",string(iround(time_many_files))," sec")
  info("  clearing multiple files took ",string(iround(time_clear_files))," sec")
  info("  reading multiple files took ",string(iround(time_read_files))," sec")
  info("  max'ing multiple files took ",string(iround(time_max_files))," sec")
  info("  deleting multiple files took ",string(iround(time_delete_files))," sec")
  info("  writing multiple files took ",string(iround(time_write_files))," sec")
  info("transfering RAM files took ",string(iround(time_ram_file))," sec")
end

# ECONNREFUSED: h09u20 x3
#=
macro retry(x)
  quote
    for i=1:10
      try
        $x
        break
      catch e
        i==10 ? error(e) : (warn(e);  sleep(10))
      end
    end
  end
end
=#

function rmcontents(dir, available)
  function get_available(dir,msg)
    free = int(split(readchomp(ignorestatus(`df $dir`)))[11])
    info(string(signif(free/1024/1024,4,2))," GB available on ",dir," at ",msg)
    free
  end
  available=="before" && (free=get_available(dir,"end"))
  for file in readdir(dir)
    try;  rm(joinpath(dir,file), recursive=true);  end
  end
  available=="after" && (free=get_available(dir,"start"))
  free
end
