using Base.Test
using Images

include("../check_logfiles.jl")

function check_images(scratchpath, correct_nchannels, correct_ntiffs, black_and_white)
  logfiles = readdir(joinpath(scratchpath,"logfile_scratch"))

  # correct number of images, and are they black & white or not?
  ntiffs=0
  shades=Vector{Vector{Float32}}[]
  for (root, dirs, files) in walkdir(joinpath(scratchpath,"results"))
    for file in files
      if endswith(file,".tif")
        ntiffs+=1
        channel = parse(Int, split(file,'.')[end-1])
        while length(shades)<channel+1
          push!(shades,[])
        end
        img = load(joinpath(root,file))
        push!(shades[1+channel], unique(img))
      end
    end
  end
  @test ntiffs == correct_ntiffs
  @test length(shades) == correct_nchannels
  if black_and_white
    for shade in shades
      @test all(x->length(x).<=2, shade)
    end
  else
    for shade in shades
      @test any(x->length(x).>2, shade)
    end
  end
  shades
end

@testset "hollowcube" begin

@testset "onechannel-$v" for v in ["local", "cluster"]
  check_logfiles( joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/onechannel-$v"),
      64+1)
  check_images( joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/onechannel-$v"),
      1, 64+8+1, true)
end

@testset "threechannel-$v" for v in ["local", "cluster"]
  check_logfiles(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/threechannel-$v"),
      3*(64+1))
  shades = check_images(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/threechannel-$v"),
      3, 3*(64+8+1), true)
  @test max(map(maximum, shades[1])...) > max(map(maximum, shades[2])...) > max(map(maximum, shades[3])...)
end

@testset "linearinterp" begin
  check_logfiles(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/linearinterp"),
      64+1)
  check_images(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/linearinterp"),
      1, 64+8+1, false)
end

@testset "nslots" begin
  check_logfiles(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/nslots"),
      64+1)
  check_images(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/nslots"),
      1, 64+8+1, true)

  function nslots(scratchpath, rightanswer)
    r = "MANAGER: $rightanswer CPUs"
    squatters = filter(file->contains(file,"squatter"), readdir(joinpath(scratchpath,"logfile_scratch")))
    ncache = []
    for squatter in squatters
      log = readlines(joinpath(scratchpath,"logfile_scratch",squatter))
      @test any(line->startswith(line,r), log)
      idx = findfirst(line->startswith(line,"MANAGER: allocated RAM for"), log)
      push!(ncache, parse(Int, split(log[idx])[5]))
    end
    @test length(unique(ncache))==1
    ncache[1]
  end
  ncache16a = nslots(
      joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/onechannel-cluster"), 16)
  ncache16b = nslots(
      joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/threechannel-cluster"), 16)
  ncache32 = nslots(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/nslots"), 32)
  @test ncache16a == ncache16b == div(ncache32,2)
end

end
