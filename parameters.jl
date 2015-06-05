const voxelsize_um=[0.25, 0.25, 1]  # desired pixel size.
# voxelsize_used_um, in destination/calculated_parameters.jl, is that actually used.
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,

const countof_leaf=120e6  # maximum number of pixels in output tiles

const countof_job=480e9  # number of pixels in sub bounding boxes.
# size to use all of RAM

const nnodes = 32  # number of non-GPU 32-core compute nodes to use, max is 32

const source="/groups/mousebrainmicro/mousebrainmicro/stitch/2014-10-06/Stitch9_corners"
const destination="/tier2/mousebrainmicro/render/stitch9"

const shared_scratch="/nobackup/mousebrainmicro/scratch/<yourId>"
const logfile_scratch="/groups/mousebrainmicro/mousebrainmicro/scratch/<yourId>"  # should be on /groups
const delete_scratch="as-you-go"   # "at-end" or "as-you-go"

const nchannels=2  # need to generalize
const file_infix="ngc"  # need to generalize

# normalized origin and shape of sub-bounding box to render
const region_of_interest=([0,0,0], [1,1,1])  # e.g. ([0,0.5,0], [0.5,0.5,0.5]) == octant three
# use the following code to convert morton order to origin & shape
#morton = [8,1,7,3]
#const region_of_interest = (
#    squeeze(sum( [(((morton[depth]-1)>>xyz)&1)/2^depth for xyz=0:2, depth=1:length(morton)] ,2),2),
#    fill(0.5^length(morton),3) )

const notify_addr = "<yourId>@janelia.hhmi.org"
const bill_userid = "<yourId>"

const bad_nodes = []  # e.g. ["h09u20"]

const interpolation = "nearest"  # "linear" or "nearest"

# build the octree with a function below.  should return uint16

# the simplest and fastest
downsampling_function(arg::Array{Uint16,3}) = arg[1,1,1]

# equivalent to mean(arg) but 30x faster and half the memory
#downsampling_function(arg::Array{Uint16,3}) = uint16(sum(arg)>>3)

# 2nd brightest of the 8 pixels
# equivalent to sort(reshape(arg,8))[7] but half the time and a third the memory usage
#function downsampling_function(arg::Array{Uint16,3})
#  m0::Uint16 = 0x0000
#  m1::Uint16 = 0x0000
#  for i = 1:8
#    @inbounds tmp::Uint16 = arg[i]
#    if tmp>m0
#      m1=m0
#      m0=tmp
#    elseif tmp>m1
#      m1=tmp
#    end
#  end
#  m1
#end
