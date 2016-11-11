const voxelsize_um=[1.0, 1.0, 1.0]  # desired pixel size.
# voxelsize_used_um, in destination/calculated_parameters.jl, is that actually used.
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,

const max_pixels_per_leaf=50^3  # maximum number of pixels in output tiles

const max_tiles_per_job=1000  # maximum number of input tiles per cluster job
# size to use all of RAM

const which_cluster = [ENV["HOSTNAME"]] # "janelia" or ["hostname1", "hostname2", "hostname3", ...]
const bad_nodes = []  # e.g. ["h09u20"]

const throttle_leaf_nmachines = 32  # number of compute nodes to use to render leafs
# for which_cluster=="janelia" set to 32 (max is 96)
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_nmachines = 32  # number of compute nodes to use to downsample octree
# for which_cluster=="janelia" set to 32
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_njobs_per_machine = Sys.CPU_CORES>>1
# for which_cluster=="janelia" set to 1
# otherwise set to ncores per machine for small data sets

const throttle_octree_ncores_per_job = 1
# for which_cluster=="janelia" set to 9 (max is 16)
# otherwise set to 1 for small data sets

const short_queue = true  # rendering MUST take less than 1 hour

const scratchpath=joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch")

const source=joinpath(scratchpath,"data/onechannel") # path to tilebase.cache.yml
const destination=joinpath(scratchpath,"onechannel-local","results")  # path to octree

const shared_scratch=joinpath(scratchpath,"onechannel-local","shared_scratch")
const logfile_scratch=joinpath(scratchpath,"onechannel-local","logfile_scratch")  # should be on /groups
const delete_scratch="as-you-go"   # "at-end" or "as-you-go"

const file_infix="hollowcube"
const file_format="tif"  # "tif" or "h5"

# normalized origin and shape of sub-bounding box to render
const region_of_interest=([0,0,0], [1,1,1])  # e.g. ([0,0.5,0], [0.5,0.5,0.5]) == octant three

# or use the following code to convert morton order to origin & shape
#morton_order = [8,1,7,3]
#const region_of_interest = (
#    squeeze(sum(
#        [(((morton_order[depth]-1)>>xyz)&1)/2^depth for xyz=0:2, depth=1:length(morton_order)] ,2),2),
#    fill(0.5^length(morton_order),3) )

const include_origins_outside_roi=false   # set to true to render all of small test ROI

const notify_addr = "arthurb@hhmi.org"
const bill_userid = "arthurb"

const interpolation = "nearest"  # "nearest" or "linear"

const raw_compression_ratios = [] # or e.g. [10,80]
const octree_compression_ratios = []

# build the octree with a function below.  should return uint16

# the simplest and fastest
downsampling_function(arg::Array{UInt16,3}) = (@inbounds return arg[1,1,1])

# equivalent to mean(arg) but 30x faster and half the memory
#downsampling_function(arg::Array{UInt16,3}) = UInt16(sum(arg)>>3)

# 2nd brightest of the 8 pixels
# equivalent to sort(reshape(arg,8))[7] but half the time and a third the memory usage
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

# the below are for testing purposes.  users shouldn't need to change.
const dry_run = false
const use_avx = true
const system_ram = 32e9
