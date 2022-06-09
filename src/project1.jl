# project 3D octree to 2D quadtree at full resolution

# src/project1.jl <full-path-to-parameters-file> <face_leaf_path_idx>

# e.g. src/project1.jl /home/arthurb/projects/mouselight/src/render/project-parameters.jl 1024

const parameters_file = ARGS[1]
const face_leaf_path_idx = parse(Int,ARGS[2]) - 1

using YAML

include(parameters_file)
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))
include(joinpath(frompath,"calculated_parameters.jl"))
include(joinpath(frompath,"set_parameters.jl"))

face_leaf_path_init = string(face_leaf_path_idx, base=4, pad=nlevels)
if axis==1
  remap(x) = replace(replace(replace(replace(x, '3' =>'7'), '2' =>'5'), '1' =>'3'), '0' =>'1')
elseif axis==2
  remap(x) = replace(replace(replace(replace(x, '3' =>'6'), '2' =>'5'), '1' =>'2'), '0' =>'1')
elseif axis==3
  remap(x) = replace(replace(replace(replace(x, '3' =>'4'), '2' =>'3'), '1' =>'2'), '0' =>'1')
end
face_leaf_path = [Int(x)-Int('0') for x in remap(face_leaf_path_init)] 
@info string("face_leaf_path = ", face_leaf_path)


leaf_paths=[]
crop_offset=0
found_surface=false
for i = 0:2^nlevels-1
  global crop_offset, found_surface
  leaf_path = face_leaf_path + reverse([(i>>n)&1 for n in 0:nlevels-1]) * 2^(axis-1)
  in_path = joinpath(frompath, join(leaf_path,Base.Filesystem.path_separator))
  if isdir(in_path)
    push!(leaf_paths, leaf_path)
    found_surface=true
  elseif !found_surface
    crop_offset+=1
  end
end
@info string("length(leaf_paths) = ", length(leaf_paths))
isempty(leaf_paths) && exit()


crop_range = Vector{Int}(undef, 2)
if crop_um[1]==-Inf
  crop_from = 1
else
  crop_from = round(Int,(crop_um[1]-origin_nm[axis]/1000)/voxelsize_used_um[axis])
  crop_from = max(1, crop_from - crop_offset*shape_leaf_px[axis])
end
if crop_um[2]==+Inf
  crop_to = shape_leaf_px[axis]*length(leaf_paths)
else
  crop_to = round(Int,(crop_um[2]-origin_nm[axis]/1000)/voxelsize_used_um[axis])
  crop_to = min(shape_leaf_px[axis]*length(leaf_paths), crop_to - crop_offset*shape_leaf_px[axis])
end
crop_range = (:)(crop_from, crop_to)
@info string("crop_range = ", crop_range)
isempty(crop_range) && exit()


const tiles = TileBaseOpen(frompath)
tile_shape = TileShape(TileBaseIndex(tiles,1))

tile_size = (shape_leaf_px...,nchannels)
stack_size = [tile_size...]
stack_size[axis] *= length(leaf_paths)
stack = Array{UInt16}(undef, stack_size...);

for ileaf in eachindex(leaf_paths)
  @info ileaf
  in_path = joinpath(frompath, join(leaf_paths[ileaf],Base.Filesystem.path_separator))
  read_img = load_tile(string(in_path,"/default"), file_format_save, tile_size)
  stack_index = Any[:,:,:,:]
  stack_index[axis] = (ileaf-1)*tile_size[axis]+1 : ileaf*tile_size[axis]
  stack[stack_index...] = read_img
end

permuted_stack = PermutedDimsArray(stack, [setdiff(1:3,axis)..., axis, 4]);


projection_img = Array{UInt16}(undef, size(permuted_stack)[1:2]...)

function scale_and_clamp(arg::Vector, black_level, white_level)
  signed_arg = convert(Vector{Float32}, arg)
  scaled_arg = (signed_arg .- black_level) ./ (white_level .- black_level)
  typemax(UInt16).*clamp.(scaled_arg,0,1)
end

for x=1:size(permuted_stack,1), y=1:size(permuted_stack,2)
  signal = scale_and_clamp(permuted_stack[x,y,:,signal_channel],
        signal_black_level, signal_white_level)
  reference = scale_and_clamp(permuted_stack[x,y,:,reference_channel],
        reference_black_level, reference_white_level)
  projection_tile = projection_function(signal - reference)
  projection_img[x,y] = round(UInt16, clamp(projection_tile, 0, typemax(UInt16)))
end


mkpath(joinpath(topath,"tiles"))
out_path = joinpath(topath, "tiles", join(face_leaf_path))
@info string("saving to ",out_path)
save(string(out_path,".",file_format_save),
     Gray.(reinterpret.(N0f16, PermutedDimsArray(projection_img,(2,1)))))
