using Base.Test, Images

include(joinpath(ENV["RENDER_PATH"],"src/render/test/basictests.jl"))

function check_permissions(basepath)
  for (root, dirs, files) in walkdir(basepath)
    for file in files
      @test filemode(joinpath(basepath,root,file)) & 0o020 > 0
    end
    for dir in dirs
      @test filemode(joinpath(basepath,root,dir)) & 0o020 > 0
    end
  end
end

#ndio-tiff is not compatible with ImageMagick.  0x7fff = 0x7f7f, hence the .>>8
function check_toplevel_images(basepath, nchannels)
  for nchannel=0:(nchannels-1)
    img = load(joinpath(basepath,"default.$(nchannel).tif"))
    rightanswer = zeros(UInt16,48);  rightanswer[3:end-1]=0xffff>>nchannel
    @test squeeze(maximum(raw(img),(1,2)),(1,2)).>>8 == rightanswer.>>8
    rightanswer = zeros(UInt16,48);  rightanswer[4:end-2]=0xffff>>nchannel
    @test squeeze(maximum(raw(img),(1,3)),(1,3)).>>8 == rightanswer.>>8
    rightanswer = zeros(UInt16,48);  rightanswer[6:end-4]=0xffff>>nchannel
    @test squeeze(maximum(raw(img),(2,3)),(2,3)).>>8 == rightanswer.>>8
  end
end

scratchpath = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch")

@testset "hollowcube" begin

@testset "onechannel-$v" for v in ["local", "cluster"]
  check_permissions(joinpath(scratchpath,"onechannel-$v","results"))
  check_logfiles(joinpath(scratchpath,"onechannel-$v","logfile_scratch"), 64+1)
  check_toplevel_images(joinpath(scratchpath,"onechannel-$v","results"),1)
end

@testset "onechannel local-vs-cluster" begin
  check_images(scratchpath, ["onechannel-local/results", "onechannel-cluster/results"], 1, 64+8+1, true)
end

@testset "threechannel-$v" for v in ["local", "cluster"]
  check_permissions(joinpath(scratchpath,"threechannel-$v","results"))
  check_logfiles(joinpath(scratchpath,"threechannel-$v","logfile_scratch"), 64+1)
  check_toplevel_images(joinpath(scratchpath,"threechannel-$v","results"),2)
end

@testset "threechannel local-vs-cluster" begin
  shades = check_images(scratchpath, ["threechannel-local/results", "threechannel-cluster/results"], 3, 3*(64+8+1), true)
  @test max(map(maximum, shades[1])...) > max(map(maximum, shades[2])...) > max(map(maximum, shades[3])...)
end

@testset "linearinterp" begin
  check_logfiles(joinpath(scratchpath,"linearinterp-onechannel","logfile_scratch"), 64+1)
  check_images(scratchpath, ["linearinterp-onechannel/results"], 1, 64+8+1, false)
  check_logfiles(joinpath(scratchpath,"linearinterp-threechannel","logfile_scratch"), 64+1)
  check_logfiles(joinpath(scratchpath,"linearinterp-threechannel-cpu","logfile_scratch"), 64+1)
  check_images(scratchpath, ["linearinterp-threechannel/results","linearinterp-threechannel-cpu/results"], 3, 3*(64+8+1), false)
  info("it is normal to have 68 avx images each have ~1000 voxels be 257 shades different compared to cpu")
end

@testset "nslots" begin
  check_logfiles(joinpath(scratchpath,"nslots","logfile_scratch"), 64+1)
  check_images(scratchpath, ["onechannel-cluster/results", "nslots/results"], 1, 64+8+1, true)
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
  @test div(ncache16a,3) == ncache16b == div(ncache32,6)
end

@testset "keepscratch" begin
  check_permissions(joinpath(scratchpath,"keepscratch","results"))
  check_permissions(joinpath(scratchpath,"keepscratch","shared_scratch"))
  check_logfiles(joinpath(scratchpath,"keepscratch","logfile_scratch"), 64+1)
  check_images(scratchpath, ["onechannel-local/results", "keepscratch/results"], 1, 64+8+1, true)
  check_toplevel_images(joinpath(scratchpath,"keepscratch","results"),1)

  @test !isdir(joinpath(scratchpath,"onechannel-local","shared_scratch"))
  @test !isdir(joinpath(scratchpath,"onechannel-cluster","shared_scratch"))
  @test isdir(joinpath(scratchpath,"keepscratch","shared_scratch"))
  @test length(collect(walkdir(joinpath(scratchpath,"keepscratch","shared_scratch")))) == 73
end

end
