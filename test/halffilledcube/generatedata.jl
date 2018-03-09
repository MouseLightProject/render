const shape_leaf_px = [1024, 1536, 251]
const nchannels = 1
const tile_type = convert(Cint,1)
const raw_compression_ratios = []

const testpath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch/data")

include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

using Base.Test

in_tile_jl = zeros(UInt16,shape_leaf_px...)
in_tile_jl[1+(end>>1):end, :, :] = 0xffff
for i=1:21
  save_tile(testpath, @sprintf("00/000%02d",i), @sprintf("000%02d-halffilledcube",i), "tif", in_tile_jl)
end
