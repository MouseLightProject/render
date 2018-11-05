const voxelsize_um=[0.25, 0.25, 1]  # desired pixel size
# voxelsize_used_um, in destination/calculated_parameters.jl, is that actually used.
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,

const max_pixels_per_leaf=120e6  # maximum number of pixels in output tiles

const max_tiles_per_job=1000  # maximum number of input tiles per cluster job
# larger is more efficient with file i/o; smaller is more parallel computation

const which_cluster = "janelia" # "janelia" or ["hostname1", "hostname2", "hostname3", ...]
const bad_nodes = []  # e.g. ["h09u20"]

const ncores_incluster = 48*32
 
const throttle_leaf_ncores_per_job = 16
# for which_cluster=="janelia" set based on memory and load utilization (max is 48)

const throttle_leaf_njobs = 1  # maximum number of compute nodes to use to render leafs
# for which_cluster=="janelia" set to 16 (max is 32)
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_nmachines = 1  # maximum number of compute nodes to use to downsample octree
# for which_cluster=="janelia" set to 32
# otherwise this parameter is ignored, and is taken to be length(which_cluster)

const throttle_octree_njobs_per_machine = min(8,Sys.CPU_CORES)
# for which_cluster=="janelia" set to 1
# otherwise set to ncores per machine for small data sets

const throttle_octree_ncores_per_job = 9
# for which_cluster=="janelia" set to 9 (max is 16)
# otherwise set to 1 for small data sets

const short_queue = false  # rendering leaf nodes MUST take less than 1 hour

const overall_time_limit = short_queue ? 60 : 4320  # three days
const leaf_time_limit    = short_queue ? 60 : 2880  # two days
const octree_time_limit  = 480   # eight hours
const cleanup_time_limit = 60    # one hour

const source="/home/arthurb/projects/mouselight/src/render/test/regression"  # path to tilebase.cache.yml
const destination="/nrs/mouselight/arthurb/987roiprod"  # path to octree

const shared_scratch="/nrs/mouselight/arthurb/scratch/987roiprod"
const logfile_scratch="/groups/mousebrainmicro/mousebrainmicro/scratch/arthurb/987roiprod"  # should be on /groups
const delete_scratch="as-you-go"   # "at-end" or "as-you-go"

const nchannels=2
const file_infix="ngc"
const file_format="tif"  # or, e.g., h5

# normalized origin and shape of sub-bounding box to render
const region_of_interest=([0.4,0.4,0.4], [0.3,0.25,0.2])  # e.g. ([0,0.5,0], [0.5,0.5,0.5]) == octant three
# use the following code to convert morton order to origin & shape
#morton_order = [8,1,7,3]
#const region_of_interest = (
#    squeeze(sum(
#        [(((morton_order[depth]-1)>>xyz)&1)/2^depth for xyz=0:2, depth=1:length(morton_order)] ,2),2),
#    fill(0.5^length(morton_order),3) )

const include_origins_outside_roi=true   # set to true to render all of small test ROI

const notify_addr = "arthurb@hhmi.org"
const bill_userid = "arthurb"

const interpolation = "nearest"  # "nearest" or "linear"

const raw_compression_ratios = [] # or e.g. [10,80]
const octree_compression_ratios = []
const downsample_from_existing_leaves=false

const dry_run = false

# build the octree with a function below.  should return UInt16

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
