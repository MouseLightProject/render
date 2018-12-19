const bill_userid = "mouselight"

const frompath = "/nrs/mouselight/SAMPLES/..."  # the octree output of src/render
const topath = "/groups/mousebrainmicro/mousebrainmicro/users/..."

const signal_channel = 1
const reference_channel = 2

const signal_black_level = 16474
const signal_white_level = 40787
const reference_black_level = 11795
const reference_white_level = 50763

const axis = 1  # 1=sagittal, 2=transverse, or 3=coronal

const crop_um = [-Inf,Inf]

projection_function(arg) = maximum(arg[crop_range])
#projection_function(arg) = quantile(arg[crop_range],0.999)
#projection_function(arg) = maximum(mapwindow(median!, arg, 5)[crop_range])

# 2nd brightest
#=
function projection_function(arg)
  m0 = 0
  m1 = 0
  for i in crop_range
    @inbounds tmp = arg[i]
    if tmp>m0
      m1=m0
      m0=tmp
    elseif tmp>m1
      m1=tmp
    end
  end
  m1
end
=#

const output_pixel_sizes_um = [1,3,10,30]

const which_cluster = "janelia"  # "janelia" or ["hostname1", "hostname2", "hostname3", ...]
const throttle = 256  # maximum number of jobs to submit

const delete_scratch="yes"   # "yes" or "no"
