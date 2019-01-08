using Distributed, Serialization, SharedArrays

const um2nm=1e3

function get_available_port(default_port)
  port = default_port
  while true
    try
      server = listen(IPv4(0),port)
      return server, port
    catch
      port+=1
    end
  end
end

has_avx2 = occursin("avx2", read("/proc/cpuinfo", String))


# port of tilebase

TileBaseOpen(source) = YAML.load_file(joinpath(source,"tilebase.cache.yml"))
TileBaseIndex(tiles, idx) = tiles["tiles"][idx]
TileBaseCount(tiles) = length(tiles["tiles"])
TileBasePath(tiles) = tiles["path"]

function TileBaseAABB(tiles)
  out = nothing
  for tile in tiles["tiles"]
    out = AABBUnion(out,TileAABB(tile))
  end
  out
end

TileShape(tile) = tile["shape"]["dims"]
TileAABB(tile) = tile["aabb"]
TilePath(tile) =  tile["path"]
TileFree(tile) = nothing

function AABBHit(bbox1,bbox2)
  @assert length(bbox1["ori"])==length(bbox2["ori"])
  for i=1:length(bbox1["ori"])
    mnmx = bbox1["ori"][i] + bbox1["shape"][i]
    mxmn = bbox1["ori"][i]
    mnmx = min(mnmx, bbox2["ori"][i] + bbox2["shape"][i])
    mxmn = max(mxmn, bbox2["ori"][i])
    mnmx<=mxmn && return false
  end
  return true
end

AABBMake(ndim) = Dict("ori"=>Vector{Int}(undef, ndim), "shape"=>Vector{Int}(undef, ndim))
AABBGet(bbox) = bbox["ori"], bbox["shape"]
AABBVolume(bbox) = prod(bbox["shape"])

function AABBSet(bbox, ori, shape)
  if ori!=nothing
    bbox["ori"]=ori
  end
  if shape!=nothing
    bbox["shape"]=shape
  end
end

function AABBUnion(bbox1,bbox2)
  if bbox1==nothing
    bbox1 = deepcopy(bbox2)
  end
  @assert length(bbox1["ori"])==length(bbox2["ori"])
  os = max.(bbox1["ori"]+bbox1["shape"], bbox2["ori"]+bbox2["shape"])
  o = min.(bbox1["ori"],bbox2["ori"])
  AABBSet(bbox1, o, os-o)
  bbox1
end

function AABBBinarySubdivision(bbox)
  out=Vector{Dict}(undef, 8)
  for i=1:8
    out[i]=deepcopy(bbox)
    for d=1:3
      s=out[i]["shape"][d]
      h=s>>1
      r=s-h<<1
      out[i]["shape"][d]=h
      if ((i-1)>>(d-1))&1==1
        out[i]["ori"][d]+=h
        out[i]["shape"][d]+=r
      end
    end
  end
  return out
end


function isleaf(bbox)
  c = AABBVolume(bbox) / (prod(voxelsize_used_um)*um2nm^3)
  c < max_pixels_per_leaf
end


# interface to mltk-bary

const libengine = ENV["RENDER_PATH"]*"/env/build/mltk-bary/libengine.so"

#closelibs() = Libdl.dlclose(h)

mutable struct BarycentricException <: Exception end

BarycentricCPUinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricCPUinit, libengine),
      Int, (Ptr{Ptr{Cvoid}},Ref{Cuint},Ref{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricAVXinit(r,src_shape,dst_shape,ndims) = ccall((:BarycentricAVXinit, libengine),
      Int, (Ptr{Ptr{Cvoid}},Ref{Cuint},Ref{Cuint},Cuint),
      r,src_shape,dst_shape,ndims) !=1 && throw(BarycentricException())

BarycentricCPUresample(r,cube,orientation,interpolation) =
      ccall((:BarycentricCPUresample, libengine), Int, (Ptr{Ptr{Cvoid}},Ref{Cfloat},Cint,Cint),
      r,cube,orientation,interpolation=="nearest" ? 0 : 1) !=1 && throw(BarycentricException())

BarycentricAVXresample(r,cube,orientation,interpolation) =
      ccall((:BarycentricAVXresample, libengine), Int, (Ptr{Ptr{Cvoid}},Ref{Cfloat},Cint,Cint),
      r,cube,orientation,interpolation=="nearest" ? 0 : 1) !=1 && throw(BarycentricException())

BarycentricCPUrelease(r) = ccall((:BarycentricCPUrelease, libengine), Cvoid, (Ptr{Ptr{Cvoid}},), r)
BarycentricAVXrelease(r) = ccall((:BarycentricAVXrelease, libengine), Cvoid, (Ptr{Ptr{Cvoid}},), r)

for f = ("source", "destination", "result")
  @eval $(Symbol("BarycentricCPU"*f))(r,src) =
      ccall(($("BarycentricCPU"*f), libengine), Int, (Ptr{Ptr{Cvoid}},Ref{UInt16}),
          r,src) !=1 && throw(BarycentricException())
  @eval $(Symbol("BarycentricAVX"*f))(r,src) =
      ccall(($("BarycentricAVX"*f), libengine), Int, (Ptr{Ptr{Cvoid}},Ref{UInt16}),
          r,src) !=1 && throw(BarycentricException())
end


# below used by director, manager, render, merge, ...

subtile_corner_indices(ix,iy,iz) =
    Int[ (1 .+
          [ix-1+b&1  iy-1+(b>>1)&1  iz-1+(b>>2)&1]*
          [1, length(xlims), length(xlims)*length(ylims)]
         )[1] for b=0:7 ]

function calc_in_subtiles_aabb(tile,xlims,ylims,zlims,transform_nm)
  in_subtiles_aabb = Array{Dict}(undef, length(xlims)-1, length(ylims)-1, length(zlims)-1)
  origin, shape = AABBGet(TileAABB(tile))
  for ix=1:length(xlims)-1, iy=1:length(ylims)-1, iz=1:length(zlims)-1
    it = subtile_corner_indices(ix,iy,iz)
    sub_origin = dropdims(minimum(transform_nm[:,it], dims=2), dims=2)
    sub_shape =  dropdims(maximum(transform_nm[:,it], dims=2), dims=2) - sub_origin
    in_subtiles_aabb[ix,iy,iz] = AABBMake(3)
    AABBSet(in_subtiles_aabb[ix,iy,iz], sub_origin, sub_shape)
  end
  in_subtiles_aabb
end

load_tile(filename,ext,shape) = retry(() -> _load_tile(filename,ext,shape),
    delays=ExponentialBackOff(n=10, first_delay=60, factor=3, max_delay=60*60*24),
    check=(s,e)->(@info string("load_tile($filename,$ext,$shape) failed.  will retry."); true))()

function _load_tile(filename,ext,shape)
  if ext=="tif"
    regex = Regex("$(basename(filename)).[0-9].$ext")
    files = filter(x->occursin(regex,x), readdir(dirname(filename)))
    @assert length(files)==shape[end]
    img = Array{UInt16}(undef, shape...)
    for (c,file) in enumerate(files)
      img[:,:,:,c] = rawview(channelview(load(string(filename,'.',c-1,'.',ext), false)))
    end
    return img
  else
    tdata = h5read(string(filename,'.',ext), "/data")
    reshape(tdata,size(tdata)[1:end-1])
  end 
end

save_tile(filesystem, path, basename, ext, data) = retry(
    () -> _save_tile(filesystem, path, basename, ext, data),
    delays=ExponentialBackOff(n=10, first_delay=60, factor=3, max_delay=60*60*24),
    check=(s,e)->(@info string("save_tile($filesystem,$path,$basename,$ext).  will retry."); true))()

function _save_tile(filesystem, path, basename, ext, data)
  filepath = joinpath(filesystem,path)
  retry(()->mkpath(filepath),
      delays=ExponentialBackOff(n=10, first_delay=60, factor=3, max_delay=60*60*24),
      check=(s,e)->(@info string("mkpath(\"$filepath\").  will retry."); true))()
  if ext=="tif"
    for c=1:size(data,4)
      save(string(joinpath(filepath,basename),'.',c-1,'.',ext), data[:,:,:,c], false)
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
  ix = ((coord-1)>>0)&1 * (shape_leaf_px[1]>>1)
  iy = ((coord-1)>>1)&1 * (shape_leaf_px[2]>>1)
  iz = ((coord-1)>>2)&1 * (shape_leaf_px[3]>>1)
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
    @info string("moving from ",from_file)
    @info string("  to ",to_file)
    mv(from_file,to_file)
  else
    @info string("copying from ",from_file)
    @info string("  to ",to_file)
    cp(from_file,to_file)
  end
end

function _merge_across_filesystems(destination, prefix, suffix, out_tile_path, recurse, octree, delete, flag,
      in_tiles, out_tile_img, out_tile_img_down)
  time_octree_read = time_octree_down = time_octree_save = 0.0
  time_single_file = time_many_files = time_clear_files = 0.0
  time_read_files = time_max_files = time_delete_files = time_write_files = 0.0

  merge1 = Array{UInt16}(undef, shape_leaf_px...,nchannels)

  retry(()->mkpath(joinpath(destination,out_tile_path)),
        delays=ExponentialBackOff(n=10, first_delay=60, factor=3, max_delay=60*60*24),
        check=(s,e)->(@info string("mkpath(\"$(joinpath(destination,out_tile_path))\").  will retry."); true))()
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
    @info string("merging:")
    t1=time()
    fill!(merge1, 0x0000)
    time_clear_files=(time()-t1)
    for in_tile in in_tiles
      @info string("  reading ",in_tile,".%.",suffix)
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
            @info string("  deleting ",from_file)
            rm(from_file)
          end
        else
          from_file = string(in_tile,'.',suffix)
          @info string("  deleting ",from_file)
          rm(from_file)
        end
      end
      time_delete_files+=(time()-t1)
    end
    @info string("  copying to ",destination2)
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
      @info string("saving output tile ",out_tile_path," to ",destination2)
      save_tile(destination, out_tile_path, prefix, suffix, out_tile_img)
      time_octree_save=(time()-t0)
    end
    if flag
      t0=time()
      @info string("downsampling output tile ",out_tile_path)
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

  typeof(r) <: Exception && rethrow(r)

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

  @info string("copying / moving single files took ",round(time_single_file, sigdigits=4)," sec")
  @info string("merging multiple files took ",round(time_many_files, sigdigits=4)," sec")
  @info string("  clearing multiple files took ",round(time_clear_files, sigdigits=4)," sec")
  @info string("  reading multiple files took ",round(time_read_files, sigdigits=4)," sec")
  @info string("  max'ing multiple files took ",round(time_max_files, sigdigits=4)," sec")
  @info string("  deleting multiple files took ",round(time_delete_files, sigdigits=4)," sec")
  @info string("  writing multiple files took ",round(time_write_files, sigdigits=4)," sec")

  if octree
    @info string("clearing octree took ",round(time_octree_clear, sigdigits=4)," sec")
    @info string("reading octree took ",round(time_octree_read, sigdigits=4)," sec")
    @info string("downsampling octree took ",round(time_octree_down, sigdigits=4)," sec")
    @info string("saving octree took ",round(time_octree_save, sigdigits=4)," sec")
  end
end

function rmcontents(dir, available, prefix)
  function get_available(dir,msg)
    free = parse(Int,split(readchomp(ignorestatus(`df $dir`)))[11])
    @info string(prefix,round(free/1024/1024, sigdigits=4)," GB available on ",dir," at ",msg)
    free
  end
  available=="before" && (free=get_available(dir,"end"))
  for file in readdir(dir)
    try
      rm(joinpath(dir,file), recursive=true)
    catch e
      @warn string("can't delete",joinpath(dir,file),": ",e)
    end
  end
  available=="after" && (free=get_available(dir,"start"))
  free
end
