const shape_leaf_px = [16, 32, 64]
const nchannels = 3
const tile_type = convert(Cint,1)
const raw_compression_ratios = []

const datapath = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/data")

include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

using Base.Test

inset = 4
in_tile_1_jl = zeros(UInt16,shape_leaf_px...,nchannels)

in_tile_1_jl[inset:end, inset:end, inset    , :] = 0xffff
in_tile_1_jl[inset:end, inset,     inset:end, :] = 0xffff
in_tile_1_jl[inset,     inset:end, inset:end, :] = 0xffff
in_tile_1_jl[:,:,:,2].>>=1
in_tile_1_jl[:,:,:,3].>>=2
save_tile(joinpath(datapath,"threechannel"), "00/00001", "00001-hollowcube", "tif", in_tile_1_jl)

in_tile_2_jl = flipdim(in_tile_1_jl, 1)
save_tile(joinpath(datapath,"threechannel"), "00/00002", "00002-hollowcube", "tif", in_tile_2_jl)

in_tile_3_jl = flipdim(in_tile_1_jl, 2)
save_tile(joinpath(datapath,"threechannel"), "00/00003", "00003-hollowcube", "tif", in_tile_3_jl)

in_tile_4_jl = flipdim(in_tile_3_jl, 1)
save_tile(joinpath(datapath,"threechannel"), "00/00004", "00004-hollowcube", "tif", in_tile_4_jl)

in_tile_5_jl = flipdim(in_tile_1_jl, 3)
save_tile(joinpath(datapath,"threechannel"), "00/00005", "00005-hollowcube", "tif", in_tile_5_jl)

in_tile_6_jl = flipdim(in_tile_5_jl, 1)
save_tile(joinpath(datapath,"threechannel"), "00/00006", "00006-hollowcube", "tif", in_tile_6_jl)

in_tile_7_jl = flipdim(in_tile_5_jl, 2)
save_tile(joinpath(datapath,"threechannel"), "00/00007", "00007-hollowcube", "tif", in_tile_7_jl)

in_tile_8_jl = flipdim(in_tile_7_jl, 1)
save_tile(joinpath(datapath,"threechannel"), "00/00008", "00008-hollowcube", "tif", in_tile_8_jl)

run(`rsync --exclude \*\[12\].tif -r $(joinpath(datapath,"threechannel","00")) $(joinpath(datapath,"onechannel"))`)

yml_file1 = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/onechannel-tilebase.cache.yml")
yml_data1 = read(yml_file1)
yml_data1 = replace(String(yml_data1),"RENDER_PATH",ENV["RENDER_PATH"])
write(joinpath(datapath,"onechannel/tilebase.cache.yml"),yml_data1)
yml_data3 = replace(String(yml_data1),"onechannel","threechannel")
yml_data3 = replace(String(yml_data3),"[16, 32, 64, 1]","[16, 32, 64, 3]")
write(joinpath(datapath,"threechannel/tilebase.cache.yml"),yml_data3)
