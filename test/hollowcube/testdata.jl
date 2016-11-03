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

  # correct number of images, and are they black & white?
  ntiffs=0
  shades=Vector{Vector{Float32}}[[],[],[]]
  for (root, dirs, files) in walkdir(joinpath(scratchpath,"results"))
    for file in files
      if endswith(file,".tif")
        ntiffs+=1
        channel = parse(Int, split(file,'.')[end-1])
        img = load(joinpath(root,file))
        push!(shades[1+channel], unique(img))
      end
    end
  end
  nmergelogs, ntiffs, shades
end

@testset "hollowcube" begin

@testset "onechannel-$v" for v in ["local", "cluster"]
  nmergelogs, ntiffs, shades = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/onechannel-$v"))
  @test nmergelogs == 64+1
  @test ntiffs == 64+8+1
  @test all(x->length(x).<=2, shades[1])
  @test length(shades[2])==0
  @test length(shades[3])==0
end

@testset "threechannel-$v" for v in ["local", "cluster"]
  nmergelogs, ntiffs, shades = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/threechannel-$v"))
  @test nmergelogs == 3*(64+1)
  @test ntiffs == 3*(64+8+1)
  @test all(x->length(x).<=2, shades[1])
  @test all(x->length(x).<=2, shades[2])
  @test all(x->length(x).<=2, shades[3])
  @test max(map(maximum, shades[1])...) > max(map(maximum, shades[2])...) > max(map(maximum, shades[3])...)
end

@testset "linearinterp" begin
  nmergelogs, ntiffs, shades = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch/linearinterp"))
  @test nmergelogs == 64+1
  @test ntiffs == 64+8+1
  @test any(x->length(x).>2, shades[1])
  @test length(shades[2])==0
  @test length(shades[3])==0
end

end
