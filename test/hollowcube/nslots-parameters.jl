const notify_addr = "arthurb@hhmi.org"
const bill_userid = "scicompsoft"

const scratchpath=joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch")
const source=joinpath(scratchpath,"data/onechannel") # path to tilebase.cache.yml
const destination=joinpath(scratchpath,"nslots","results")  # path to octree

const file_infix="hollowcube"
const file_format="tif"  # "tif" or "h5"

const shared_scratch=joinpath(scratchpath,"nslots","shared_scratch")
const logfile_scratch=joinpath(scratchpath,"nslots","logfile_scratch")  # should be on /groups
const delete_scratch="as-you-go"   # "never", "at-end" or "as-you-go"

const voxelsize_um=[1.0, 1.0, 1.0]  # desired pixel size
# voxelsize_used_um, in destination/calculated_parameters.jl, is that actually used.
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,

const interpolation = "nearest"  # "nearest" or "linear"

const raw_compression_ratios = [] # or e.g. [10,80]
const octree_compression_ratios = []


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
#    squeeze(sum(
#        [(((morton_order[depth]-1)>>xyz)&1)/2^depth for xyz=0:2, depth=1:length(morton_order)] ,2),2),
#    fill(0.5^length(morton_order),3) )

const include_origins_outside_roi=false   # set to true to render all of small test ROI


const max_pixels_per_leaf=50^3  # maximum number of pixels in output tiles
const leaf_dim_divisible_by=2    # each dim of leafs should be divisible by this

const max_tilechannels_per_job=500  # maximum number of input tiles * nchannels per cluster job
# larger is more efficient with file i/o; smaller is more parallel computation


const which_cluster = "janelia" # "janelia" or ["hostname1", "hostname2", "hostname3", ...]
const bad_nodes = []  # e.g. ["h09u20"]

const ncores_incluster = 48*32
 
const throttle_leaf_ncores_per_job = 32
# for which_cluster=="janelia" set based on memory and load utilization (max is 48)

const throttle_leaf_njobs = 96  # maximum number of compute nodes to use to render leafs
# for which_cluster=="janelia" set to 96 (max is 96)
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_njobs = 256  # maximum number of compute nodes to use to downsample octree
# for which_cluster=="janelia" set to 256 (max is 512)
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_njobs_per_machine = min(8,Sys.CPU_CORES)
# ignored when which_cluster=="janelia"
# otherwise set to ncores per machine for small data sets

const throttle_octree_ncores_per_job = 9
# for which_cluster=="janelia" set to 9 (max is 16)
# otherwise set to 1 for small data sets

const short_queue = true  # rendering MUST take less than 1 hour


# the below are for testing purposes.  users shouldn't need to change.
const dry_run = false
const use_avx = true
const peon_ram = 15*1024^3
const other_ram = (10+5)*1024^3   # system + manager
