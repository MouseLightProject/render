using Base.Test
using Images

function basictests(scratchpath, correct_nchannels, correct_nmergelogs, correct_ntiffs, black_and_white)
  logfiles = readdir(joinpath(scratchpath,"logfile_scratch"))

  # all log files exist?
  @test any(logfiles.=="render.log")
  @test any(logfiles.=="director.log")
  @test any(logfiles.=="monitor.log")
  @test any(file->startswith(file,"squatter"), logfiles)
  @test sum(map(x->startswith(x, "merge"), logfiles)) == correct_nmergelogs

  # any errors reported in the log files?
  for logfile in logfiles
    log = read(joinpath(scratchpath,"logfile_scratch",logfile))
    @test !contains(String(log), "ERR")
    @test !contains(String(log), "WAR")
    @test !contains(String(log), "Segmentation")
  end

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
  basictests( joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/onechannel-$v"),
      1, 64+1, 64+8+1, true)
end

@testset "threechannel-$v" for v in ["local", "cluster"]
  shades = basictests(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/threechannel-$v"),
      3, 3*(64+1), 3*(64+8+1), true)
  @test max(map(maximum, shades[1])...) > max(map(maximum, shades[2])...) > max(map(maximum, shades[3])...)
end

@testset "linearinterp" begin
  basictests(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/linearinterp"),
      1, 64+1, 64+8+1, false)
end

@testset "nslots" begin
  basictests(joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/nslots"),
      1, 64+1, 64+8+1, true)

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
