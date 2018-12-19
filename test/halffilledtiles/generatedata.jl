const shape_leaf_px = [1024, 1536, 251]
const nchannels = 1
const tile_type = convert(Cint,1)
const raw_compression_ratios = []

const datapath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledtiles/scratch/data")

include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

in_tile_jl = zeros(UInt16,shape_leaf_px...)
in_tile_jl[1+(end>>1):end, :, :] = 0xffff
for i=1:21
  save_tile(datapath, @sprintf("00/000%02d",i), @sprintf("000%02d-halffilledtiles",i), "tif", in_tile_jl)
end

yml_file = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledtiles/tilebase.cache.yml")
yml_data = read(yml_file)
yml_data = replace(String(yml_data),"RENDER_PATH" =>ENV["RENDER_PATH"])
write(joinpath(datapath,"tilebase.cache.yml"),yml_data)
