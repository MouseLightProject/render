const bill_userid = "scicompsoft"

const frompath = ENV["RENDER_PATH"]*"/src/render/test/hollowcube/scratch/threechannel-cluster/results"  # the octree output of src/render
const topath = ENV["RENDER_PATH"]*"/src/render/test/hollowcube/scratch/projection-coronal-cluster"

const signal_channel = 1
const reference_channel = 2

const signal_black_level = 1
const signal_white_level = 65535
const reference_black_level = 1
const reference_white_level = 65535

const axis = 3  # 1=sagittal, 2=transverse, or 3=coronal

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
const throttle = 16  # maximum number of jobs to submit

const delete_scratch="no"   # "yes" or "no"
