const um2nm=1e3

macro retry(x)
  n=3; s=10
  quote
    for i=1:$n
      try
        $x
        break
      catch e
        i==$n ? error(e) : (warn($(string(x)));  sleep($s))
      end
    end
  end
end

function get_available_port(default_port)
  port = default_port
  while true
    try
      server = listen(port)
      return server, port
    catch
      port+=1
    end
  end
end

# interface to CUDA

# map(x->(cudaSetDevice(x); [cudaMemGetInfo()...]./1024^3), 0:cudaGetDeviceCount()-1)

#=
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
=#

# nvidia's unified virtual addressing causes memory swap problems with multiple peons, so
# turn off GPU detection until this is fixed
#try
#  global ngpus = cudaGetDeviceCount()
#catch
  global ngpus = 0
#end

has_avx2 = contains(readstring("/proc/cpuinfo"),"avx2")

# interface to tilebase

const libtilebase = ENV["RENDER_PATH"]*"/env/lib/libtilebase.so"

TileBaseOpen(source) = ccall((:TileBaseOpen, libtilebase), Ptr{Void}, (Ptr{UInt8},Ptr{UInt8}), source, C_NULL)
TileBaseClose(tiles) = ccall((:TileBaseClose, libtilebase), Void, (Ptr{Void},), tiles)
TileBaseAABB(tiles) = ccall((:TileBaseAABB, libtilebase), Ptr{Void}, (Ptr{Void},), tiles)
TileBaseCount(tiles) = ccall((:TileBaseCount, libtilebase), Csize_t, (Ptr{Void},), tiles)
TileBaseIndex(tiles, idx) = ccall((:TileBaseIndex, libtilebase), Ptr{Void}, (Ptr{Void},Cuint), tiles,idx-1)

TileAABB(tile) = ccall((:TileAABB, libtilebase), Ptr{Void}, (Ptr{Void},), tile)
TileShape(tile) = ccall((:TileShape, libtilebase), Ptr{Void}, (Ptr{Void},), tile)
TileFile(tile) = ccall((:TileFile, libtilebase), Ptr{Void}, (Ptr{Void},), tile)
TilePath(tile) = ccall((:TilePath, libtilebase), Ptr{UInt8}, (Ptr{Void},), tile)
TileFree(tile) = ccall((:TileFree, libtilebase), Ptr{Void}, (Ptr{Void},), tile)

AABBMake(ndim) = ccall((:AABBMake, libtilebase), Ptr{Void}, (Csize_t,), ndim)
AABBFree(bbox) = ccall((:AABBFree, libtilebase), Void, (Ptr{Void},), bbox)
AABBGet(bbox,ndim,ori,shape) = ccall((:AABBGet, libtilebase),
    Ptr{Void}, (Ptr{Void},Ptr{Csize_t},Ptr{Ptr{Int}},Ptr{Ptr{Int}}), bbox,ndim,ori,shape)
AABBSet(bbox,ndim,ori,shape) = ccall((:AABBSet, libtilebase),
    Ptr{Void}, (Ptr{Void},Csize_t,Ptr{Int},Ptr{Int}), bbox,ndim,ori,shape)
AABBVolume(bbox) = ccall((:AABBVolume, libtilebase), Cdouble, (Ptr{Void},), bbox)
AABBNDim(bbox) = ccall((:AABBNDim, libtilebase), Csize_t, (Ptr{Void},), bbox)
AABBHit(bbox1,bbox2) = 1==ccall((:AABBHit, libtilebase), Cint, (Ptr{Void},Ptr{Void}), bbox1,bbox2)
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
  ndim[1], unsafe_wrap(Array,origin[1],ndim[1]), unsafe_wrap(Array,shape[1],ndim[1])
end

# interface to nd

const libnd = ENV["RENDER_PATH"]*"/env/lib/libnd.so"

ndinit() = ccall((:ndinit, libnd), Ptr{Void}, ())
ndheap(nd_t) = ccall((:ndheap, libnd), Ptr{Void}, (Ptr{Void},), nd_t)
ndfree(nd_t) = ccall((:ndfree, libnd), Void, (Ptr{Void},), nd_t)
nddata(nd_t) = ccall((:nddata, libnd), Ptr{Void}, (Ptr{Void},), nd_t)
ndtype(nd_t) = ccall((:ndtype, libnd), Cint, (Ptr{Void},), nd_t)
ndkind(nd_t) = ccall((:ndkind, libnd), Cint, (Ptr{Void},), nd_t)
ndndim(nd_t) = ccall((:ndndim, libnd), Cuint, (Ptr{Void},), nd_t)
ndcopy_ip(nd_t_dst, nd_t_src) =
    ccall((:ndcopy_ip, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void}), nd_t_dst, nd_t_src)
ndcast(nd_t,t) = ccall((:ndcast, libnd), Ptr{Void}, (Ptr{Void},Cint), nd_t,t)
ndfill(nd_t,c) = ccall((:ndfill, libnd), Ptr{Void}, (Ptr{Void},UInt64), nd_t,c)
ndref(nd_t,data,kind) = ccall((:ndref, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void},Cint), nd_t,data,kind)
ndnbytes(nd_t) = ccall((:ndnbytes, libnd), Csize_t, (Ptr{Void},), nd_t)
ndShapeSet(nd_t, idim, val) =
    ccall((:ndShapeSet, libnd), Ptr{Void}, (Ptr{Void},Cuint,Csize_t), nd_t, idim-1, val)
ndioOpen(filename,format,mode) =
    ccall((:ndioOpen, libnd), Ptr{Void}, (Ptr{UInt8},Ptr{Void},Ptr{UInt8}), filename, format, mode)
ndioRead(file,dst) = ccall((:ndioRead, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void}), file, dst)
ndioReadSubarray(file,dst,origin,shape) =
    ccall((:ndioReadSubarray, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void},Ptr{Csize_t},Ptr{Csize_t}),
    file, dst, origin, shape)
ndioWrite(file,src) = ccall((:ndioWrite, libnd), Ptr{Void}, (Ptr{Void},Ptr{Void}), file, src)
ndioClose(file) = ccall((:ndioClose, libnd), Void, (Ptr{Void},), file)
ndioShape(file) = ccall((:ndioShape, libnd), Ptr{Void}, (Ptr{Void},), file)

retain_for_gc = Any[]

for f in ("ndshape", "ndstrides")
  @eval function $(Symbol(f))(nd_t)
    push!(retain_for_gc, convert(Array{Cuint}, unsafe_wrap(Array,  # hack: size_t -> Cuint
        ccall(($f, libnd), Ptr{Csize_t}, (Ptr{Void},), nd_t)
        ,ndndim(nd_t))) )
    pointer(retain_for_gc[end])
  end
  @eval function $(Symbol(f*"J"))(nd_t)  # memory leak?
    unsafe_wrap(Array,
        ccall(($f, libnd), Ptr{Csize_t}, (Ptr{Void},), nd_t)
        ,ndndim(nd_t))
  end
end

# interface to mltk-bary

#h=Libdl.dlopen("libcudart.so",Libdl.RTLD_LAZY|Libdl.RTLD_DEEPBIND|Libdl.RTLD_GLOBAL)
const libengine = ENV["RENDER_PATH"]*"/env/build/mltk-bary/libengine.so"

#closelibs() = Libdl.dlclose(h)

type BarycentricException <: Exception end

BarycentricCPUinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricCPUinit, libengine),
      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricAVXinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricAVXinit, libengine),
      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

#BarycentricGPUinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricGPUinit, libengine),
#      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
#      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricCPUresample(r,cube,orientation,interpolation) =
      ccall((:BarycentricCPUresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat},Cint,Cint),
      r,cube,orientation,interpolation=="nearest" ? 0 : 1) !=1 && throw(BarycentricException())

BarycentricAVXresample(r,cube,orientation,interpolation) =
      ccall((:BarycentricAVXresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat},Cint,Cint),
      r,cube,orientation,interpolation=="nearest" ? 0 : 1) !=1 && throw(BarycentricException())

#BarycentricGPUresample(r,cube) = ccall((:BarycentricGPUresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat}),
#      r,cube) !=1 && throw(BarycentricException())

BarycentricCPUrelease(r) = ccall((:BarycentricCPUrelease, libengine), Void, (Ptr{Ptr{Void}},), r)
BarycentricAVXrelease(r) = ccall((:BarycentricAVXrelease, libengine), Void, (Ptr{Ptr{Void}},), r)
#BarycentricGPUrelease(r) = ccall((:BarycentricGPUrelease, libengine), Void, (Ptr{Ptr{Void}},), r)

for f = ("source", "destination", "result")
  @eval $(Symbol("BarycentricCPU"*f))(r,src) =
      ccall(($("BarycentricCPU"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{UInt16}),
          r,src) !=1 && throw(BarycentricException())
  @eval $(Symbol("BarycentricAVX"*f))(r,src) =
      ccall(($("BarycentricAVX"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{UInt16}),
          r,src) !=1 && throw(BarycentricException())
  #@eval $(Symbol("BarycentricGPU"*f))(r,src) =
  #    ccall(($("BarycentricGPU"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{UInt16}),
  #        r,src) !=1 && throw(BarycentricException())
end

# port some of tilebase/app/render

function isleaf(bbox)
  c = AABBVolume(bbox) / (prod(voxelsize_used_um)*um2nm^3)
  c < max_pixels_per_leaf
end

# below used by director, manager, render, merge, ...

subtile_corner_indices(ix,iy,iz) =
    Int[ (1+
          [ix-1+b&1  iy-1+(b>>1)&1  iz-1+(b>>2)&1]*
          [1, length(xlims), length(xlims)*length(ylims)]
         )[1] for b=0:7 ]

function calc_in_subtiles_aabb(tile,xlims,ylims,zlims,transform_nm)
  in_subtiles_aabb = Array(Ptr{Void}, length(xlims)-1, length(ylims)-1, length(zlims)-1)
  origin, shape = AABBGetJ(TileAABB(tile))[2:3]
  for ix=1:length(xlims)-1, iy=1:length(ylims)-1, iz=1:length(zlims)-1
    it = subtile_corner_indices(ix,iy,iz)
    sub_origin = minimum(transform_nm[:,it],2)
    sub_shape =  maximum(transform_nm[:,it],2) - sub_origin
    in_subtiles_aabb[ix,iy,iz] = AABBMake(3)
    AABBSet(in_subtiles_aabb[ix,iy,iz], 3, sub_origin, sub_shape)
  end
  in_subtiles_aabb
end

function ndalloc(tileshape, tiletype, heap=true)
  tmp_ws = ndinit()
  for (i,x) in enumerate(tileshape)
    ndShapeSet(tmp_ws, i, x)
  end
  ndcast(tmp_ws, tiletype)
  heap || return tmp_ws
  tile_ws=ndheap(tmp_ws)
  ndfree(tmp_ws)
  tile_ws
end

:shape_leaf_px in names(Main) && (save_ws = ndalloc(shape_leaf_px, tile_type, false))

function save_out_tile(filesystem, path, name, data::AbstractArray{UInt16})
  ndref(save_ws, pointer(data), convert(Cint,0))   # 0==nd_heap;  need to generalize
  save_out_tile(filesystem, path, name, save_ws)
end

function save_out_tile(filesystem, path, name, data::Ptr{Void})
  try
    filepath = joinpath(filesystem,path)
    filename = joinpath(filepath,name)
    @retry mkpath(filepath)
    ndioClose(ndioWrite(ndioOpen(filename, C_NULL, "w"), data))
    for ratio in raw_compression_ratios
      run(`$(ENV["RENDER_PATH"])/src/mj2/compressfiles/run_compressbrain_cluster.sh /usr/local/matlab-2014b $ratio $filename $filepath $(splitext(name)[1]) 0`)
    end
  catch
    error("in save_out_tile")
  end
end

# the merge API could perhaps be simplified. complexity arises because it is called:
# by render to build the octree                       (recurse=n/a,    octree=true,  delete=false)
# by manager.jl to handle overflow into local_scratch (recurse=false,  octree=false, delete=true)
# by merge to combine multiple previous renders       (recurse=either, octree=false, delete=false)

function downsample(out_tile_jl, coord, shape_leaf_px, scratch)
  ix = (((coord-1)>>0)&1 * shape_leaf_px[1]>>1)
  iy = (((coord-1)>>1)&1 * shape_leaf_px[2]>>1)
  iz = (((coord-1)>>2)&1 * shape_leaf_px[3]>>1)
  for z=1:2:shape_leaf_px[3]-1
    tmpz = iz + (z+1)>>1
    for y=1:2:shape_leaf_px[2]-1
      tmpy = iy + (y+1)>>1
      for x=1:2:shape_leaf_px[1]-1
        tmpx = ix + (x+1)>>1
        @inbounds out_tile_jl[tmpx, tmpy, tmpz] = downsampling_function(scratch[x:x+1, y:y+1, z:z+1])
      end
    end
  end
end

function _merge_across_filesystems(
      destination, prefix, chantype, out_tile_path, recurse, octree, delete, flag,
      in_tiles, out_tile_img, out_tile_img_down)
  merge1_ws = ndalloc(shape_leaf_px, tile_type)
  merge1_jl = unsafe_wrap(Array{UInt16,3},convert(Ptr{UInt16},nddata(merge1_ws)), tuple(shape_leaf_px...))

  time_octree_down=0.0; time_octree_save=0.0
  time_single_file=0.0; time_many_files=0.0; time_clear_files=0.0
  time_read_files=0.0;   time_max_files=0.0; time_delete_files=0.0; time_write_files=0.0

  @retry mkpath(joinpath(destination,out_tile_path))
  destination2 = joinpath(destination, out_tile_path, prefix * chantype)

  if length(in_tiles)==1 && in_tiles[1]!=destination2
    t0=time()
    info("copying from ",in_tiles[1])
    info("  to ",destination2)
    cp(in_tiles[1],destination2)
    delete && (info("  deleting ",in_tiles[1]); rm(in_tiles[1]))
    time_single_file=(time()-t0)
  elseif length(in_tiles)>1
    t0=time()
    merge2_ws = ndalloc(shape_leaf_px, tile_type)
    merge2_jl = unsafe_wrap(Array{UInt16,3},convert(Ptr{UInt16},nddata(merge2_ws)), tuple(shape_leaf_px...))
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
      merge1_jl[:,:,:] = max(merge1_jl,merge2_jl)
      time_max_files=(time()-t1)
      t1=time()
      delete && (info("  deleting ",in_tile); rm(in_tile))
      time_delete_files=(time()-t1)
    end
    info("  copying to ",destination2)
    t1=time()
    save_out_tile(destination, out_tile_path, prefix * chantype, merge1_jl)
    time_write_files=(time()-t1)
    ndfree(merge2_ws)
    time_many_files=(time()-t0)
  end

  if octree
    if length(in_tiles)==1
      ndioClose(ndioRead(ndioOpen( in_tiles[1], C_NULL, "r" ),merge1_ws))
    elseif length(in_tiles)==0
      t0=time()
      info("saving output tile ",out_tile_path," to ",destination2)
      save_out_tile(destination, out_tile_path, prefix * chantype, out_tile_img)
      time_octree_save=(time()-t0)
    end
    if flag
      t0=time()
      info("downsampling output tile ",out_tile_path)
      last_morton_coord = parse(Int,out_tile_path[end])
      scratch::Array{UInt16,3} = length(in_tiles)==0 ? out_tile_img : merge1_jl
      downsample(out_tile_img_down, last_morton_coord, shape_leaf_px, scratch)
      time_octree_down=(time()-t0)
    end
  end

  ndfree(merge1_ws)
  time_octree_down, time_octree_save,
        time_single_file, time_many_files, time_clear_files,
        time_read_files, time_max_files, time_delete_files, time_write_files
end

merge_across_filesystems(source::String, destination, prefix, chantype, out_tile_path,
      recurse::Bool, octree::Bool, delete::Bool) =
  merge_across_filesystems([source], destination, prefix, chantype, out_tile_path, recurse, octree, delete)

function accumulate_times(r)
  global time_octree_down, time_octree_save
  global time_single_file, time_many_files, time_clear_files
  global time_read_files, time_max_files, time_delete_files, time_write_files

  time_octree_down  += r[1]
  time_octree_save  += r[2]
  time_single_file  += r[3]
  time_many_files   += r[4]
  time_clear_files  += r[5]
  time_read_files   += r[6]
  time_max_files    += r[7]
  time_delete_files += r[8]
  time_write_files  += r[9]
end

function merge_across_filesystems(sources::Array{String,1}, destination, prefix, chantype, out_tile_path,
      recurse::Bool, octree::Bool, delete::Bool, flag=false, out_tile_img_down=nothing)
  global time_octree_clear

  dirs=String[]
  in_tiles=String[]
  for source in sources
    isdir(joinpath(source,out_tile_path)) || continue
    listing = readdir(joinpath(source,out_tile_path))
    dir2 = map(x->isdir(joinpath(source,out_tile_path,x)), listing)
    sum(dir2)==0 || push!(dirs, listing[dir2]...)
    in_tiles2 = [joinpath(source,out_tile_path,x)
          for x in listing[!dir2 & map(x->endswith(x,chantype), listing)]]
    isempty(in_tiles2) || push!(in_tiles, in_tiles2...)
  end

  length(dirs)==0 && length(in_tiles)==0 && return

  out_tile_img=nothing
  if octree && length(dirs)>0 && length(in_tiles)==0
    t0=time()
    out_tile_img = SharedArray(UInt16, shape_leaf_px...)
    fill!(out_tile_img, 0x0000)
    time_octree_clear+=(time()-t0)
  end

  futures=[]

  ((!octree && recurse) || (octree && length(in_tiles)==0)) && for dir in unique(dirs)
    push!(futures,
        merge_across_filesystems(sources, destination, prefix, chantype, joinpath(out_tile_path,dir),
          recurse, octree, delete, true, out_tile_img) )
  end

  foreach(f->accumulate_times(fetch(f)), futures)

  remotecall(_merge_across_filesystems, default_worker_pool(),
        destination, prefix, chantype, out_tile_path, recurse, octree, delete,
        flag, in_tiles, out_tile_img, out_tile_img_down)
end

function merge_output_tiles(source, destination, prefix, chantype, out_tile_path,
      recurse::Bool, octree::Bool, delete::Bool)
  global time_octree_clear=0.0, time_octree_down=0.0, time_octree_save=0.0
  global time_single_file=0.0, time_many_files=0.0
  global time_clear_files=0.0, time_read_files=0.0, time_max_files=0.0
  global time_delete_files=0.0, time_write_files=0.0

  accumulate_times(fetch(merge_across_filesystems(
        source, destination, prefix, chantype, out_tile_path, recurse, octree, delete)))

  info("copying single files took ",string(signif(time_single_file,4))," sec")
  info("merging multiple files took ",string(signif(time_many_files,4))," sec")
  info("  clearing multiple files took ",string(signif(time_clear_files,4))," sec")
  info("  reading multiple files took ",string(signif(time_read_files,4))," sec")
  info("  max'ing multiple files took ",string(signif(time_max_files,4))," sec")
  info("  deleting multiple files took ",string(signif(time_delete_files,4))," sec")
  info("  writing multiple files took ",string(signif(time_write_files,4))," sec")

  if octree
    info("clearing octree took ",string(signif(time_octree_clear,4))," sec")
    info("downsampling octree took ",string(signif(time_octree_down,4))," sec")
    info("saving octree took ",string(signif(time_octree_save,4))," sec")
  end
end

function rmcontents(dir, available, prefix)
  function get_available(dir,msg)
    free = parse(Int,split(readchomp(ignorestatus(`df $dir`)))[11])
    info(string(signif(free/1024/1024,4))," GB available on ",dir," at ",msg, prefix=prefix)
    free
  end
  available=="before" && (free=get_available(dir,"end"))
  for file in readdir(dir)
    try
      rm(joinpath(dir,file), recursive=true)
    catch
      warn("can't delete",joinpath(dir,file))
    end
  end
  available=="after" && (free=get_available(dir,"start"))
  free
end
