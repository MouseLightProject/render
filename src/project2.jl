# abut and downsample 2D quadtree to single image

# src/project2.jl <full-path-to-parameters-file>

# e.g. src/project2.jl /home/arthurb/projects/mouselight/src/render/project-parameters.jl

const parameters_file = ARGS[1]

using Images, YAML, Morton

include(parameters_file)
include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))
include(joinpath(frompath,"calculated_parameters.jl"))
include(joinpath(frompath,"set_parameters.jl"))

shape_tile_px = shape_leaf_px[setdiff(1:3,axis)]

projection_size = [shape_tile_px*(2^nlevels)...]
projection_img = fill(0x0000, projection_size...);

tif_files = filter(x->occursin(r"^[1-8].*\.tif",x), readdir(joinpath(topath,"tiles")));
for tile in unique([split(x,'.')[1] for x in tif_files])
  info(tile)
  in_path = joinpath(topath,"tiles",tile)
  img = load(in_path*'.'*file_format_save)

  quadtree_path = [parse(Int,x) for x in tile[1:nlevels]]
  if axis==1
    quadtree_path[quadtree_path.==3] = 2
    quadtree_path[quadtree_path.==5] = 3
    quadtree_path[quadtree_path.==7] = 4
  elseif axis==2
    quadtree_path[quadtree_path.==5] = 3
    quadtree_path[quadtree_path.==6] = 4
  end
  cartesian_coord = tree2cartesian(quadtree_path)
  cartesian_coord_pix = round.(Int, cartesian_coord/2^length(quadtree_path).*projection_size)
  cartesian_box = repeat(cartesian_coord_pix; inner=2) -
                         [-1+shape_tile_px[1], 0, -1+shape_tile_px[2], 0]
  ix = colon(cartesian_box[1:2]...)
  iy = colon(cartesian_box[3:4]...)
  projection_img[ix,iy] = transpose(rawview(channelview(img)));
end

out_path = joinpath(topath, "tiles", "projection-$(projection_size[1])x$(projection_size[2])")
info("saving to ",out_path)
flip = projection_size[1]>projection_size[2]
save(out_path*'.'*file_format_save, flip ? transpose(projection_img) : projection_img)

for output_pixel_size_um in output_pixel_sizes_um
  downsample_by = output_pixel_size_um ./ voxelsize_used_um[setdiff(1:3,axis)]
  downsample_size = round.(Int, projection_size./downsample_by)

  sigma = map((o,n)->0.75*o/n, projection_size[1:2], downsample_size[1:2])
  kern = KernelFactors.gaussian(sigma)
  downsample_img = round.(UInt16, imresize(imfilter(projection_img, kern, NA()), downsample_size...))

  out_path = joinpath(topath, "projection-$(downsample_size[1])x$(downsample_size[2])-$(output_pixel_size_um)um")
  info("saving to ",out_path)
  flip = downsample_size[1]>downsample_size[2]
  save(out_path*'.'*file_format_save, flip ? transpose(downsample_img) : downsample_img)
end
