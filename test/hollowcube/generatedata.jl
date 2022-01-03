const shape_leaf_px = [16, 32, 64]
const nchannels = 3
const tile_type = convert(Cint,1)

const retry_n = 10
const retry_first_delay = 10
const retry_factor = 2
const retry_max_delay = 60*60

const datapath = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/data")

include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

inset = 4
in_tile_1 = zeros(UInt16,shape_leaf_px...,nchannels)

in_tile_1[inset:end, inset:end, inset    , :] .= 0xffff
in_tile_1[inset:end, inset,     inset:end, :] .= 0xffff
in_tile_1[inset,     inset:end, inset:end, :] .= 0xffff
in_tile_1[:,:,:,2].>>=1
in_tile_1[:,:,:,3].>>=2
save_tile(joinpath(datapath,"threechannel"), "00/00001", "00001-hollowcube", "tif", in_tile_1)

in_tile_2 = reverse(in_tile_1, dims=1)
save_tile(joinpath(datapath,"threechannel"), "00/00002", "00002-hollowcube", "tif", in_tile_2)

in_tile_3 = reverse(in_tile_1, dims=2)
save_tile(joinpath(datapath,"threechannel"), "00/00003", "00003-hollowcube", "tif", in_tile_3)

in_tile_4 = reverse(in_tile_3, dims=1)
save_tile(joinpath(datapath,"threechannel"), "00/00004", "00004-hollowcube", "tif", in_tile_4)

in_tile_5 = reverse(in_tile_1, dims=3)
save_tile(joinpath(datapath,"threechannel"), "00/00005", "00005-hollowcube", "tif", in_tile_5)

in_tile_6 = reverse(in_tile_5, dims=1)
save_tile(joinpath(datapath,"threechannel"), "00/00006", "00006-hollowcube", "tif", in_tile_6)

in_tile_7 = reverse(in_tile_5, dims=2)
save_tile(joinpath(datapath,"threechannel"), "00/00007", "00007-hollowcube", "tif", in_tile_7)

in_tile_8 = reverse(in_tile_7, dims=1)
save_tile(joinpath(datapath,"threechannel"), "00/00008", "00008-hollowcube", "tif", in_tile_8)

run(`rsync --exclude \*\[12\].tif -r $(joinpath(datapath,"threechannel","00")) $(joinpath(datapath,"onechannel"))`)

yml_file1 = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/onechannel-tilebase.cache.yml")
yml_data1 = read(yml_file1)
yml_data1 = replace(String(yml_data1),"RENDER_PATH" =>ENV["RENDER_PATH"])
write(joinpath(datapath,"onechannel/tilebase.cache.yml"),yml_data1)
yml_data3 = replace(String(yml_data1),"onechannel" =>"threechannel")
yml_data3 = replace(String(yml_data3),"[16, 32, 64, 1]" =>"[16, 32, 64, 3]")
write(joinpath(datapath,"threechannel/tilebase.cache.yml"),yml_data3)
