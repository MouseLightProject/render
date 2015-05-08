const voxelsize_um=[0.25, 0.25, 1]  # desired pixel size.
# voxelsize_used_um is that actually used,
#   adjusted to make tile widths even and tile volume a multiple of 32*32*4,
#   saved in destination/calculated_parameters.jl

const countof_leaf=120e6  # maximum number of pixels in output tiles

const countof_job=120e9  # number of pixels in sub bounding boxes.
# size to use all of RAM and local_scratch
#   or, it might be faster to size to just RAM;  need to test

const nnodes = 32  # number of non-GPU 32-core compute nodes to use, max is 32

const source="/groups/mousebrainmicro/mousebrainmicro/stitch/2014-10-06/Stitch9_corners"
const destination="/tier2/mousebrainmicro/render/stitch9"

const shared_scratch="/nobackup/mousebrainmicro/scratch"
#const shared_scratch="/groups/mousebrainmicro/mousebrainmicro/scratch"

const nchannels=2  # need to generalize
const file_infix="ngc"  # need to generalize

# normalized origin and shape of sub-bounding box to render
const region_of_interest=([0,0,0], [1,1,1])  # e.g. ([0,0.5,0], [0.5,0.5,0.5]) == octant three

const notify_addr = "<yourId>@janelia.hhmi.org"
const bill_userid = "<yourId>"

const bad_nodes = []  # e.g. ["h09u20"]


# the function to use to build the octree.  should return uint16

# 2nd brightest of the 8 pixels
# equivalent to sort(reshape(arg,8))[7] but half the time and a third the memory usage
function downsampling_function(arg::Array{Uint16,3})
  m0::Uint16 = 0x0000
  m1::Uint16 = 0x0000
  for i = 1:8
    @inbounds tmp::Uint16 = arg[i]
    if tmp>m0
      m1=m0
      m0=tmp
    elseif tmp>m1
      m1=tmp
    end
  end
  m1
end

# equivalent to mean(arg) but 30x faster and half the memory
#downsampling_function(arg::Array{Uint16,3}) = uint16(sum(arg)>>3)
