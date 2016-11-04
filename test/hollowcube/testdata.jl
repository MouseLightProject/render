using Base.Test
using Images

include("../basic_tests.jl")

@testset "hollowcube" begin

scratchpath = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch")

function check_toplevel_images(basepath, nchannels)
  for nchannel=0:(nchannels-1)
    img = load(joinpath(basepath,"default.$(nchannel).tif"))
    # ImageMagic returns UInt8 instead of UInt16
    rightanswer = zeros(UInt8,48);  rightanswer[3:end-1]=0xff>>nchannel
    @test squeeze(maximum(raw(img),(1,2)),(1,2)) == rightanswer
    rightanswer = zeros(UInt8,48);  rightanswer[4:end-2]=0xff>>nchannel
    @test squeeze(maximum(raw(img),(1,3)),(1,3)) == rightanswer
    rightanswer = zeros(UInt8,48);  rightanswer[6:end-4]=0xff>>nchannel
    @test squeeze(maximum(raw(img),(2,3)),(2,3)) == rightanswer
  end
end

@testset "onechannel-$v" for v in ["local", "cluster"]
  check_logfiles(joinpath(scratchpath,"onechannel-$v"), 64+1)
  check_toplevel_images(joinpath(scratchpath,"onechannel-$v","results"),1)
end

@testset "onechannel local-vs-cluster" begin
  check_images(scratchpath, ["onechannel-local", "onechannel-cluster"], 1, 64+8+1, true)
end

@testset "threechannel-$v" for v in ["local", "cluster"]
  check_logfiles(joinpath(scratchpath,"threechannel-$v"), 3*(64+1))
  check_toplevel_images(joinpath(scratchpath,"threechannel-$v","results"),2)
end

@testset "threechannel local-vs-cluster" begin
  shades = check_images(scratchpath, ["threechannel-local", "threechannel-cluster"], 3, 3*(64+8+1), true)
  @test max(map(maximum, shades[1])...) > max(map(maximum, shades[2])...) > max(map(maximum, shades[3])...)
end

@testset "linearinterp" begin
  check_logfiles(joinpath(scratchpath,"linearinterp"), 64+1)
  check_images(scratchpath, ["linearinterp"], 1, 64+8+1, false)
end

@testset "nslots" begin
  check_logfiles(joinpath(scratchpath,"nslots"), 64+1)
  check_images(scratchpath, ["onechannel-cluster", "nslots"], 1, 64+8+1, true)
  check_toplevel_images(joinpath(scratchpath,"nslots","results"),1)

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

  ncache16a = nslots(joinpath(scratchpath,"onechannel-cluster"), 16)
  ncache16b = nslots(joinpath(scratchpath,"threechannel-cluster"), 16)
  ncache32 = nslots(joinpath(scratchpath,"nslots"), 32)
  @test ncache16a == ncache16b == div(ncache32,2)
end

end
