const notify_addr = "arthurb@hhmi.org"
const bill_userid = "scicompsoft"

const scratchpath=joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch")
const source=joinpath(scratchpath,"data/threechannel") # path to tilebase.cache.yml
const destination=joinpath(scratchpath,"threechannel-hdf5","results")  # path to octree

const local_scratch=joinpath(scratchpath,"threechannel-hdf5","local_scratch")
const shared_scratch=joinpath(scratchpath,"threechannel-hdf5","shared_scratch")
const logfile_scratch=joinpath(scratchpath,"threechannel-hdf5","logfile_scratch")  # should be on /groups
const delete_scratch="as-you-go"   # "never", "at-end" or "as-you-go"

const voxelsize_um=[1.0, 1.0, 1.0]  # desired pixel size
# voxelsize_used_um, in destination/calculated_parameters.jl, is that actually used.
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,

const interpolation = "nearest"  # "nearest" or "linear"

const downsample_from_existing_leaves=false

const file_infix="hollowcube"
const file_format_load="tif"  # "tif", "h5", or "mj2"
const file_format_save="h5"  # "tif", "h5", or "mp4"

# load and save tiles with the functions below.  the arg named `ext` is the
# file_format_{load,save} parameter above

using FileIO, HDF5, VideoIO, ImageCore

function _load_tile(filename,ext,shape)
  regex = Regex("$(basename(filename)).[0-9].$ext\$")
  files = filter(x->occursin(regex,x), readdir(dirname(filename)))
  @assert length(files)==shape[end]
  img = Array{UInt16}(undef, shape...)
  for (c,file) in enumerate(files)
    fullfilename = string(filename,'.',c-1,'.',ext)
    if ext=="tif"
      img[:,:,:,c] = rawview(channelview(PermutedDimsArray(load(fullfilename, verbose=false), (2,1,3))))
    elseif ext=="h5"
      h5open(fullfilename, "r") do fid
        dataset = keys(fid)[1]
        img[:,:,:,c] = read(fid, "/"*dataset)
      end
    elseif ext=="mj2"
      img[:,:,:,c] = rawview(channelview(PermutedDimsArray(cat(VideoIO.load(fullfilename)..., dims=3), (2,1,3))))
    end
  end
  return img
end

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

# build the octree with a function below.  should return UInt16

# 1. the simplest and fastest
downsampling_function(arg::Array{UInt16,3}) = (@inbounds return arg[1,1,1])

# 2. equivalent to mean(arg) but 30x faster and half the memory
#downsampling_function(arg::Array{UInt16,3}) = UInt16(sum(arg)>>3)

# 3. 2nd brightest of the 8 pixels
# equivalent to sort(vec(arg))[7] but half the time and a third the memory usage
#function downsampling_function(arg::Array{UInt16,3})
#  m0::UInt16 = 0x0000
#  m1::UInt16 = 0x0000
#  for i = 1:8
#    @inbounds tmp::UInt16 = arg[i]
#    if tmp>m0
#      m1=m0
#      m0=tmp
#    elseif tmp>m1
#      m1=tmp
#    end
#  end
#  m1
#end


# normalized origin and shape of sub-bounding box to render
const region_of_interest=([0,0,0], [1,1,1])  # e.g. ([0,0.5,0], [0.5,0.5,0.5]) == octant three

# or use the following code to convert morton order to origin & shape
#morton_order = [8,1,7,3]
#const region_of_interest = (
#    dropdims(sum(
#        [(((morton_order[depth]-1)>>xyz)&1)/2^depth for xyz=0:2, depth=1:length(morton_order)] ,dims=2),dims=2),
#    fill(0.5^length(morton_order),3) )

const include_origins_outside_roi=false   # set to true to render all of small test ROI


const max_pixels_per_leaf=50^3  # maximum number of pixels in output tiles
const leaf_dim_divisible_by=2    # each dim of leafs should be divisible by this

const max_tilechannels_per_job=500  # maximum number of input tiles * nchannels per cluster job
# larger is more efficient with file i/o; smaller is more parallel computation


const which_cluster = [ENV["HOSTNAME"]] # "janelia" or ["hostname1", "hostname2", "hostname3", ...]
const bad_nodes = []  # e.g. ["h09u20"]

const ncores_incluster = 48*32

const leaf_ncores_per_job = 16
# for which_cluster=="janelia" set based on memory and load utilization (max is 48)

const leaf_nthreads_per_process = 8  # should match barycentricCPU.c

const leaf_process_oversubscription = 2

const throttle_leaf_njobs = 96  # maximum number of compute nodes to use to render leafs
# for which_cluster=="janelia" set to 96 (max is 96)
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_njobs = 256  # maximum number of compute nodes to use to downsample octree
# for which_cluster=="janelia" set to 256 (max is 512)
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_njobs_per_machine = min(8,Sys.CPU_THREADS)
# ignored when which_cluster=="janelia"
# otherwise set to ncores per machine for small data sets

const octree_ncores_per_job = 1
# for which_cluster=="janelia" set to 9 (max is 16)
# otherwise set to 1 for small data sets

const short_queue = true  # rendering MUST take less than 1 hour

const overall_time_limit = short_queue ? 60 : 4320  # three days
const leaf_time_limit    = short_queue ? 60 : 2880  # two days
const octree_time_limit  = 480   # eight hours
const cleanup_time_limit = 60    # one hour
const retry_n = 10
const retry_first_delay = 10
const retry_factor = 2
const retry_max_delay = 60*60


# the below are for testing purposes.  users shouldn't need to change.
const dry_run = false
const use_avx = true
const peon_ram = 15*1024^3
const other_ram = (10+5)*1024^3   # system + manager
