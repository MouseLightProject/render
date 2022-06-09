using Printf

const shape_leaf_px = [1024, 1536, 251]
const nchannels = 1
const tile_type = convert(Cint,1)

const retry_n = 10
const retry_first_delay = 10
const retry_factor = 2
const retry_max_delay = 60*60

const datapath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledtiles/scratch/data")

include(joinpath(ENV["RENDER_PATH"],"src/render/src/admin.jl"))

function _save_tile(filesystem, path, basename0, ext, data)
  filepath = joinpath(filesystem,path)
  retry(()->mkpath(filepath),
      delays=ExponentialBackOff(n=retry_n, first_delay=retry_first_delay, factor=retry_factor, max_delay=retry_max_delay),
      check=(s,e)->(@info string("mkpath(\"$filepath\").  will retry."); true))()
  for c=1:size(data,4)
    fullfilename = string(joinpath(filepath,basename0),'.',c-1,'.',ext)
    if ext=="tif"
      save(fullfilename,
           Gray.(reinterpret.(N0f16, PermutedDimsArray(view(data,:,:,:,c), (2,1,3)))))
    elseif ext=="h5"
      h5write(fullfilename, "/data", collect(sdata(view(data,:,:,:,c))))
    elseif ext=="mp4" # mj2 gives error
      VideoIO.save(fullfilename, eachslice(view(data,:,:,:,c), dims=3))
    end
  end
end

in_tile_jl = zeros(UInt16,shape_leaf_px...,nchannels)
in_tile_jl[1+(end>>1):end, :, :, :] .= 0xffff
for i=1:21
  save_tile(datapath, @sprintf("00/000%02d",i), @sprintf("000%02d-halffilledtiles",i), "tif", in_tile_jl)
end

yml_file = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledtiles/tilebase.cache.yml")
yml_data = read(yml_file)
yml_data = replace(String(yml_data),"RENDER_PATH" =>ENV["RENDER_PATH"])
write(joinpath(datapath,"tilebase.cache.yml"),yml_data)
