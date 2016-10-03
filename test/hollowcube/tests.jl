using Base.Test
using Images

function doit(scratchpath)
  logfiles = readdir(joinpath(scratchpath,"logfile_scratch"))

  # any errors reported in logfiles?
  for logfile in logfiles
    log = read(joinpath(scratchpath,"logfile_scratch",logfile))
    @test !contains(String(log), "ERR")
    @test !contains(String(log), "WAR")
    @test !contains(String(log), "Segmentation")
  end

  # correct number of calls to merge_output_tiles()?
  nmergelogs = sum(map(x->startswith(x, "merge"), logfiles))

  # correct number of images, and they are black & white?
  ntiffs=0
  nshades=Int[]
  for (root, dirs, files) in walkdir(joinpath(scratchpath,"results"))
    for file in files
      if endswith(file,".tif")
        ntiffs+=1
        img = load(joinpath(root,file))
        push!(nshades, length(unique(img)))
      end
    end
  end
  nmergelogs, ntiffs, nshades
end

@testset "onechannel-$v" for v in ["local", "cluster"]
  nmergelogs, ntiffs, nshades = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/onechannel-$v"))
  @test nmergelogs == 64+1
  @test ntiffs == 64+8+1
  @test all(nshades.<=2)
end

@testset "threechannel-$v" for v in ["local", "cluster"]
  nmergelogs, ntiffs, nshades = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/threechannel-$v"))
  @test nmergelogs == 3*(64+1)
  @test ntiffs == 3*(64+8+1)
  @test all(nshades.<=2)
end

@testset "linearinterp" begin
  nmergelogs, ntiffs, nshades = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/linearinterp"))
  @test nmergelogs == 64+1
  @test ntiffs == 64+8+1
  @test any(nshades.>2)
end
