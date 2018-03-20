const um2nm=1e3

# from julia PR #19331

const DEFAULT_RETRY_N = 1
const DEFAULT_RETRY_ON = e->true
const DEFAULT_RETRY_MAX_DELAY = 10.0
const DEFAULT_RETRY_FIRST_DELAY = 0.05
const DEFAULT_RETRY_GROWTH_FACTOR = 5
const DEFAULT_RETRY_JITTER_FACTOR = 0.1
const DEFAULT_RETRY_MESSAGE = ""

function retry2(f::Function, retry_on::Function=DEFAULT_RETRY_ON;
            n=DEFAULT_RETRY_N,
            max_delay=DEFAULT_RETRY_MAX_DELAY,
            first_delay=DEFAULT_RETRY_FIRST_DELAY,
            growth_factor=DEFAULT_RETRY_GROWTH_FACTOR,
            jitter_factor=DEFAULT_RETRY_JITTER_FACTOR,
            message=DEFAULT_RETRY_MESSAGE)
    (args...) -> begin
        delay = min(first_delay, max_delay)
        for i = 1:n+1
            try
                return f(args...)
            catch e
                if i > n || try retry_on(e) end !== true
                    rethrow(e)
                end
            end
            jittered_delay = delay * (1.0 + (rand() * jitter_factor))
            if message!=""
              warn("try #",i," failed.  will retry in ", jittered_delay," seconds.  ",message)
              flush(STDOUT);  flush(STDERR)
            end
            sleep(jittered_delay)
            delay = min(delay * growth_factor, max_delay)
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
  ndim = Ref{Csize_t}(0)
  origin = Ref{Ptr{Int64}}(0)
  shape = Ref{Ptr{Int64}}(0)
  ccall((:AABBGet, libtilebase),
    Ptr{Void}, (Ptr{Void},Ref{Csize_t},Ref{Ptr{Int64}},Ref{Ptr{Int64}}), bbox,ndim,origin,shape)
  ndim[], unsafe_wrap(Array,origin[],ndim[]), unsafe_wrap(Array,shape[],ndim[])
end


# interface to nd

function ndshapeJ(tile_shape)
  ndim = unsafe_load(Ptr{Csize_t}(tile_shape),1)
  ptr_shape = unsafe_load(Ptr{Csize_t}(tile_shape),2)
  [unsafe_load(Ptr{Csize_t}(ptr_shape),i) for i=1:ndim]
end


# interface to mltk-bary

const libengine = ENV["RENDER_PATH"]*"/env/build/mltk-bary/libengine.so"

#closelibs() = Libdl.dlclose(h)

type BarycentricException <: Exception end

BarycentricCPUinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricCPUinit, libengine),
      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricAVXinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricAVXinit, libengine),
      Int, (Ptr{Ptr{Void}},Ptr{Cuint},Ptr{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricCPUresample(r,cube,orientation,interpolation) =
      ccall((:BarycentricCPUresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat},Cint,Cint),
      r,cube,orientation,interpolation=="nearest" ? 0 : 1) !=1 && throw(BarycentricException())

BarycentricAVXresample(r,cube,orientation,interpolation) =
      ccall((:BarycentricAVXresample, libengine), Int, (Ptr{Ptr{Void}},Ptr{Cfloat},Cint,Cint),
      r,cube,orientation,interpolation=="nearest" ? 0 : 1) !=1 && throw(BarycentricException())

BarycentricCPUrelease(r) = ccall((:BarycentricCPUrelease, libengine), Void, (Ptr{Ptr{Void}},), r)
BarycentricAVXrelease(r) = ccall((:BarycentricAVXrelease, libengine), Void, (Ptr{Ptr{Void}},), r)

for f = ("source", "destination", "result")
  @eval $(Symbol("BarycentricCPU"*f))(r,src) =
      ccall(($("BarycentricCPU"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{UInt16}),
          r,src) !=1 && throw(BarycentricException())
  @eval $(Symbol("BarycentricAVX"*f))(r,src) =
      ccall(($("BarycentricAVX"*f), libengine), Int, (Ptr{Ptr{Void}},Ptr{UInt16}),
          r,src) !=1 && throw(BarycentricException())
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
  in_subtiles_aabb = Array{Ptr{Void}}(length(xlims)-1, length(ylims)-1, length(zlims)-1)
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

load_tile(filename,ext,shape) = retry2(() -> _load_tile(filename,ext,shape),
    n=10, first_delay=60, growth_factor=3, max_delay=60*60*24,
    message="load_tile($filename,$ext,$shape)")()

function _load_tile(filename,ext,shape)
  if ext=="tif"
    regex = Regex("$(basename(filename))\.[0-9]\.$ext")
    files = filter(x->ismatch(regex,x), readdir(dirname(filename)))
    @assert length(files)==shape[end]
    img = Array{UInt16}(shape...)
    for (c,file) in enumerate(files)
      img[:,:,:,c] = PermutedDimsArray(rawview(channelview(
            load(string(filename,'.',c-1,'.',ext)))), (2,1,3))
    end
    return img
  else
    tdata = h5read(string(filename,'.',ext), "/data")
    reshape(tdata,size(tdata)[1:end-1])
  end 
end

save_tile(filesystem, path, basename, ext, data) = retry2(
    () -> _save_tile(filesystem, path, basename, ext, data),
    n=10, first_delay=60, growth_factor=3, max_delay=60*60*24,
    message="save_tile($filesystem,$path,$basename,$ext)")()

function _save_tile(filesystem, path, basename, ext, data)
  filepath = joinpath(filesystem,path)
  retry2(()->mkpath(filepath),
      n=10, first_delay=60, growth_factor=3, max_delay=60*60*24,
      message="mkpath(\"$filepath\")")()
  if ext=="tif"
    for c=1:size(data,4)
      save(string(joinpath(filepath,basename),'.',c-1,'.',ext),
           permutedims(data[:,:,:,c],(2,1,3)))
    end
  else
    tdata = reshape(sdata(data),(size(data)...,1))   # remove sdata() when fixed
    fn = string(joinpath(filepath,basename),'.',ext)
    h5write(fn, "/data", tdata)
    h5writeattr(fn, "/data", Dict("axis_tags"=>
"""{
  "axes": [
    {
      "key": "t",
      "typeFlags": 8,
      "resolution": 0,
      "description": ""
    },
    {
      "key": "c",
      "typeFlags": 1,
      "resolution": 0,
      "description": ""
    },
    {
      "key": "z",
      "typeFlags": 2,
      "resolution": 0,
      "description": ""
    },
    {
      "key": "y",
      "typeFlags": 2,
      "resolution": 0,
      "description": ""
    },
    {
      "key": "x",
      "typeFlags": 2,
      "resolution": 0,
      "description": ""
    }
  ]
}
"""))
  end
end

# the merge API could perhaps be simplified. complexity arises because it is called:
# by render to build the octree                       (recurse=n/a,    octree=true,  delete=either)
# by manager.jl to handle overflow into local_scratch (recurse=false,  octree=false, delete=true)
# by merge to combine multiple previous renders       (recurse=either, octree=false, delete=false)

function downsample(out_tile, coord, shape_leaf_px, nchannels, scratch)
  ix = ((coord-1)>>0)&1 * shape_leaf_px[1]>>1
  iy = ((coord-1)>>1)&1 * shape_leaf_px[2]>>1
  iz = ((coord-1)>>2)&1 * shape_leaf_px[3]>>1
  for c=1:nchannels
    for z=1:2:shape_leaf_px[3]-1
      tmpz = iz + (z+1)>>1
      for y=1:2:shape_leaf_px[2]-1
        tmpy = iy + (y+1)>>1
        for x=1:2:shape_leaf_px[1]-1
          tmpx = ix + (x+1)>>1
          @inbounds out_tile[tmpx, tmpy, tmpz, c] = downsampling_function(scratch[x:x+1, y:y+1, z:z+1, c])
        end
      end
    end
  end
end

function mv_or_cp(from_file, to_file, delete)
  if delete
    info("moving from ",from_file)
    info("  to ",to_file)
    mv(from_file,to_file)
  else
    info("copying from ",from_file)
    info("  to ",to_file)
    cp(from_file,to_file)
  end
end

function _merge_across_filesystems(destination, prefix, suffix, out_tile_path, recurse, octree, delete, flag,
      in_tiles, out_tile_img, out_tile_img_down)
  time_octree_read = time_octree_down = time_octree_save = 0.0
  time_single_file = time_many_files = time_clear_files = 0.0
  time_read_files = time_max_files = time_delete_files = time_write_files = 0.0

  merge1 = Array{UInt16}(shape_leaf_px...,nchannels)

  retry2(()->mkpath(joinpath(destination,out_tile_path)),
        n=10, first_delay=60, growth_factor=3, max_delay=60*60*24,
        message="mkpath(\"$(joinpath(destination,out_tile_path))\")")()
  destination2 = joinpath(destination, out_tile_path, prefix)

  if length(in_tiles)==1 && !startswith(destination2,in_tiles[1])
    t0=time()
    if suffix=="tif"
      for c=1:nchannels
        from_file = string(in_tiles[1],'.',c-1,'.',suffix)
        to_file = joinpath(destination, out_tile_path, string(prefix,'.',c-1,'.',suffix))
        mv_or_cp(from_file, to_file, delete)
      end
    else
      from_file = string(in_tiles[1],'.',suffix)
      to_file = joinpath(destination, out_tile_path, string(prefix,'.',suffix))
      mv_or_cp(from_file, to_file, delete)
    end
    time_single_file=(time()-t0)
  elseif length(in_tiles)>1
    t0=time()
    info("merging:")
    t1=time()
    fill!(merge1, 0x0000)
    time_clear_files=(time()-t1)
    for in_tile in in_tiles
      info("  reading ",in_tile,".%.",suffix)
      t1=time()
      merge2 = load_tile(in_tile, suffix, (shape_leaf_px...,nchannels))
      time_read_files+=(time()-t1)
      t1=time()
      for i4=1:nchannels, i3=1:shape_leaf_px[3], i2=1:shape_leaf_px[2], i1=1:shape_leaf_px[1]
        @inbounds merge1[i1,i2,i3,i4] = max(merge1[i1,i2,i3,i4], merge2[i1,i2,i3,i4])
      end
      time_max_files+=(time()-t1)
      t1=time()
      if delete
        if suffix=="tif"
          for c=1:nchannels
            from_file = string(in_tile,'.',c-1,'.',suffix)
            info("  deleting ",from_file)
            rm(from_file)
          end
        else
          from_file = string(in_tile,'.',suffix)
          info("  deleting ",from_file)
          rm(from_file)
        end
      end
      time_delete_files+=(time()-t1)
    end
    info("  copying to ",destination2)
    t1=time()
    save_tile(destination, out_tile_path, prefix, suffix, merge1)
    time_write_files=(time()-t1)
    time_many_files=(time()-t0)
  end

  if octree
    if length(in_tiles)==1
      t0=time()
      merge1 = load_tile(destination2,suffix, (shape_leaf_px...,nchannels))
      time_octree_read+=(time()-t0)
    elseif length(in_tiles)==0
      t0=time()
      info("saving output tile ",out_tile_path," to ",destination2)
      save_tile(destination, out_tile_path, prefix, suffix, out_tile_img)
      time_octree_save=(time()-t0)
    end
    if flag
      t0=time()
      info("downsampling output tile ",out_tile_path)
      last_morton_coord = parse(Int,out_tile_path[end])
      scratch::Array{UInt16,4} = length(in_tiles)==0 ? out_tile_img : merge1
      downsample(out_tile_img_down, last_morton_coord, shape_leaf_px, nchannels, scratch)
      time_octree_down=(time()-t0)
    end
  end

  time_octree_read, time_octree_down, time_octree_save,
        time_single_file, time_many_files, time_clear_files,
        time_read_files, time_max_files, time_delete_files, time_write_files
end

function accumulate_times(r)
  global time_octree_read, time_octree_down, time_octree_save
  global time_single_file, time_many_files, time_clear_files
  global time_read_files, time_max_files, time_delete_files, time_write_files

  time_octree_read  += r[1]
  time_octree_down  += r[2]
  time_octree_save  += r[3]
  time_single_file  += r[4]
  time_many_files   += r[5]
  time_clear_files  += r[6]
  time_read_files   += r[7]
  time_max_files    += r[8]
  time_delete_files += r[9]
  time_write_files  += r[10]
end

function merge_across_filesystems(sources::Array{String,1}, destination, prefix, suffix, out_tile_path,
      recurse::Bool, octree::Bool, delete::Bool, flag=false, out_tile_img_down=nothing)
  global time_octree_clear

  dirs=String[]
  in_tiles=String[]
  for source in sources
    isdir(joinpath(source,out_tile_path)) || continue
    listing = readdir(joinpath(source,out_tile_path))
    dir2 = map(entry->isdir(joinpath(source,out_tile_path,entry)), listing)
    sum(dir2)==0 || push!(dirs, listing[dir2]...)
    img_files = listing[.!dir2 .& map(entry->endswith(entry,suffix), listing)]
    lopoff = suffix=="tif" ? 2 : 1
    uniq_img_files = unique(map(img_file->join(split(img_file,'.')[1:end-lopoff],'.'), img_files))
    in_tiles2 = [joinpath(source,out_tile_path,uniq_img_file) for uniq_img_file in uniq_img_files]
    isempty(in_tiles2) || push!(in_tiles, in_tiles2...)
  end

  length(dirs)==0 && length(in_tiles)==0 && return fill(0.0,10)

  out_tile_img=nothing
  if octree && length(dirs)>0 && length(in_tiles)==0
    t0=time()
    out_tile_img = SharedArray{UInt16}(shape_leaf_px..., nchannels)
    fill!(out_tile_img, 0x0000)
    time_octree_clear+=(time()-t0)
  end

  futures=[]

  ((!octree && recurse) || (octree && length(in_tiles)==0)) && for dir in unique(dirs)
    push!(futures,
        merge_across_filesystems(sources, destination, prefix, suffix, joinpath(out_tile_path,dir),
          recurse, octree, delete, true, out_tile_img) )
  end

  foreach(f->accumulate_times(fetch(f)), futures)

  remotecall(_merge_across_filesystems, default_worker_pool(),
        destination, prefix, suffix, out_tile_path, recurse, octree, delete,
        flag, in_tiles, out_tile_img, out_tile_img_down)
end

merge_across_filesystems(source::String, destination, prefix, suffix, out_tile_path,
      recurse::Bool, octree::Bool, delete::Bool) =
  merge_across_filesystems([source], destination, prefix, suffix, out_tile_path,
        recurse, octree, delete)

function merge_output_tiles(source, destination, prefix, suffix, out_tile_path,
      recurse::Bool, octree::Bool, delete::Bool)
  global time_octree_clear=0.0
  global time_octree_read=0.0
  global time_octree_down=0.0
  global time_octree_save=0.0
  global time_single_file=0.0
  global time_many_files=0.0
  global time_clear_files=0.0
  global time_read_files=0.0
  global time_max_files=0.0
  global time_delete_files=0.0
  global time_write_files=0.0

  accumulate_times(fetch(merge_across_filesystems(
        source, destination, prefix, suffix, out_tile_path, recurse, octree, delete)))

  info("copying / moving single files took ",signif(time_single_file,4)," sec")
  info("merging multiple files took ",signif(time_many_files,4)," sec")
  info("  clearing multiple files took ",signif(time_clear_files,4)," sec")
  info("  reading multiple files took ",signif(time_read_files,4)," sec")
  info("  max'ing multiple files took ",signif(time_max_files,4)," sec")
  info("  deleting multiple files took ",signif(time_delete_files,4)," sec")
  info("  writing multiple files took ",signif(time_write_files,4)," sec")

  if octree
    info("clearing octree took ",signif(time_octree_clear,4)," sec")
    info("reading octree took ",signif(time_octree_read,4)," sec")
    info("downsampling octree took ",signif(time_octree_down,4)," sec")
    info("saving octree took ",signif(time_octree_save,4)," sec")
  end
end

function rmcontents(dir, available, prefix)
  function get_available(dir,msg)
    free = parse(Int,split(readchomp(ignorestatus(`df $dir`)))[11])
    info(signif(free/1024/1024,4)," GB available on ",dir," at ",msg, prefix=prefix)
    free
  end
  available=="before" && (free=get_available(dir,"end"))
  for file in readdir(dir)
    try
      rm(joinpath(dir,file), recursive=true)
    catch e
      warn("can't delete",joinpath(dir,file),": ",e)
    end
  end
  available=="after" && (free=get_available(dir,"start"))
  free
end
