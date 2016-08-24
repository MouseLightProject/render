const voxelsize_um=[0.25, 0.25, 1]  # desired pixel size.
# voxelsize_used_um, in destination/calculated_parameters.jl, is that actually used.
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,

const max_pixels_per_leaf=120e6  # maximum number of pixels in output tiles

const max_tiles_per_job=1000  # maximum number of input tiles per cluster job
# size to use all of RAM

const which_cluster = "janelia" # "janelia" or ["hostname1", "hostname2", "hostname3", ...]
const bad_nodes = []  # e.g. ["h09u20"]

const throttle_leaf = 32  # for which_cluster=="janelia", max is 32, otherwise length(which_cluster)
const throttle_octree = 32  # < ~22 per local machine
const short_queue = false  # rendering leaf nodes MUST take less than 1 hour

const source="/groups/mousebrainmicro/stitch/..."  # path to tilebase.cache.yml
const destination="/nobackup2/mouselight/..."  # path to octree

const shared_scratch="/nobackup2/mouselight/scratch/<yourId>"
const logfile_scratch="/groups/mousebrainmicro/mousebrainmicro/scratch/<yourId>"  # should be on /groups
const delete_scratch="as-you-go"   # "at-end" or "as-you-go"

const nchannels=2  # need to generalize
const file_infix="ngc"  # need to generalize

# normalized origin and shape of sub-bounding box to render
const region_of_interest=([0,0,0], [1,1,1])  # e.g. ([0,0.5,0], [0.5,0.5,0.5]) == octant three
# use the following code to convert morton order to origin & shape
#morton_order = [8,1,7,3]
#const region_of_interest = (
#    squeeze(sum(
#        [(((morton_order[depth]-1)>>xyz)&1)/2^depth for xyz=0:2, depth=1:length(morton_order)] ,2),2),
#    fill(0.5^length(morton_order),3) )
const include_origins_outside_roi=false   # set to true to render all of small test ROI

const notify_addr = "<yourId>@janelia.hhmi.org"
const bill_userid = "<yourId>"

const interpolation = "nearest"  # "linear" or "nearest"

const raw_compression_ratios = [] # or e.g. [10,80]
const octree_compression_ratios = []

const dry_run = false

# build the octree with a function below.  should return uint16

# the simplest and fastest
downsampling_function(arg::Array{UInt16,3}) = arg[1,1,1]

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
