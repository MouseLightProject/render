using Test, Images, HDF5

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

function check_toplevel_images(basepath, nchannels)
  img = load_tif_or_h5(basepath)
  @test size(img,4)==nchannels
  for ichannel=0:(nchannels-1)
    img_channel=img[:,:,:,ichannel+1]
    rightanswer = zeros(UInt16,48);  rightanswer[3:end-1]=0xffff>>ichannel
    @test squeeze(maximum(img_channel,(1,2)),(1,2)) == rightanswer
    rightanswer = zeros(UInt16,48);  rightanswer[4:end-2]=0xffff>>ichannel
    @test squeeze(maximum(img_channel,(1,3)),(1,3)) == rightanswer
    rightanswer = zeros(UInt16,48);  rightanswer[6:end-4]=0xffff>>ichannel
    @test squeeze(maximum(img_channel,(2,3)),(2,3)) == rightanswer
  end
end

function check_projection_logfiles(basepath)
  logfiledump = read(`tar xzfO $(basepath)/logs.tar.gz`, String)

  # any problems reported in the log files?
  @test !occursin("ERR", String(logfiledump))
  @test !occursin("Segmentation", String(logfiledump))
end

function check_toplevel_projection_images(basepath)
  img_color = load(joinpath(basepath,"projection-192x192.tif"))
  img = rawview(channelview(img_color))
  @test size(img)==(192,192)
  rightanswer = zeros(UInt16,192);  rightanswer[10:end-8]=0x8000
  @test squeeze(maximum(img,1),1) == rightanswer
  rightanswer = zeros(UInt16,192);  rightanswer[19:end-17]=0x8000
  @test squeeze(maximum(img,2),2) == rightanswer
end

function check_projection_images(scratchpath, testdirs, correct_nimages)
  # results directories identical?
  filess=[]
  for testdir in testdirs
    push!(filess, readdir(joinpath(scratchpath,testdir)))
    length(filess)>1 || continue
    @test filess[end-1]==filess[end]
  end

  # correct number of images, and identical?
  nimages=0
  shades=Set{UInt16}[]
  for file in filess[1]
    endswith(file,".tif") || continue
    img = load(joinpath(scratchpath,testdirs[1],file))
    nimages+=1
    imgs=Any[img]
    for testdir in testdirs[2:end]
      push!(imgs, load(joinpath(scratchpath,testdir,file)))
      if length(imgs)>1
        @test imgs[end-1] == imgs[end]
      end
    end
  end
  @test nimages == correct_nimages
end

scratchpath = joinpath(ENV["RENDER_PATH"],"src/render/test/hollowcube/scratch")

@testset "hollowcube" begin

@testset "onechannel-$v" for v in ["local", "cluster", "hdf5"]
  check_permissions(joinpath(scratchpath,"onechannel-$v","results"))
  check_logfiles(joinpath(scratchpath,"onechannel-$v","results","logs.tar.gz"), 1)
  check_toplevel_images(joinpath(scratchpath,"onechannel-$v","results"),1)
end

@testset "onechannel local-vs-cluster-vs-hdf5" begin
  check_images(scratchpath, ["onechannel-local", "onechannel-cluster", "onechannel-hdf5"], 1, 64+8+1, true)
end

@testset "threechannel-$v" for v in ["local", "cluster", "hdf5"]
  check_permissions(joinpath(scratchpath,"threechannel-$v","results"))
  check_logfiles(joinpath(scratchpath,"threechannel-$v","results","logs.tar.gz"), 1)
  check_toplevel_images(joinpath(scratchpath,"threechannel-$v","results"),3)
end

@testset "threechannel local-vs-cluster-vs-hdf5" begin
  shades = check_images(scratchpath, ["threechannel-local", "threechannel-cluster", "threechannel-hdf5"], 3, 3*(64+8+1), true)
  @test max(map(maximum, shades[1])...) > max(map(maximum, shades[2])...) > max(map(maximum, shades[3])...)
end

@testset "linearinterp" begin
  check_logfiles(joinpath(scratchpath,"linearinterp-onechannel","results","logs.tar.gz"), 1)
  check_images(scratchpath, ["linearinterp-onechannel"], 1, 64+8+1, false)
  check_logfiles(joinpath(scratchpath,"linearinterp-threechannel","results","logs.tar.gz"), 1)
  check_logfiles(joinpath(scratchpath,"linearinterp-threechannel-cpu","results","logs.tar.gz"), 1)
  check_images(scratchpath, ["linearinterp-threechannel","linearinterp-threechannel-cpu"], 3, 3*(64+8+1), false)
  @info("it is normal to have 68 avx images each have ~1000 voxels be 257 shades different compared to cpu")
end

@testset "nslots" begin
  check_logfiles(joinpath(scratchpath,"nslots","results","logs.tar.gz"), 1)
  check_images(scratchpath, ["onechannel-cluster", "nslots"], 1, 64+8+1, true)
  check_toplevel_images(joinpath(scratchpath,"nslots","results"),1)

  function nslots(scratchpath, rightanswer)
    r = "MANAGER: $rightanswer CPUs"
    logfilepath = joinpath(scratchpath,"results","logs.tar.gz")
    squatters = filter(file->occursin("squatter", file), readlines(`tar tvzf $logfilepath`))
    ncache = []
    for squatter in squatters
      squatter_file = split(squatter,' ')[end]
      log = readlines(`tar xvzfO $logfilepath $squatter_file`)
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
  check_logfiles(joinpath(scratchpath,"keepscratch","results","logs.tar.gz"), 1)
  check_images(scratchpath, ["onechannel-local", "keepscratch"], 1, 64+8+1, true)
  check_toplevel_images(joinpath(scratchpath,"keepscratch","results"),1)

  @test !isdir(joinpath(scratchpath,"onechannel-local","shared_scratch"))
  @test !isdir(joinpath(scratchpath,"onechannel-cluster","shared_scratch"))
  @test isdir(joinpath(scratchpath,"keepscratch","shared_scratch"))
  @test length(collect(walkdir(joinpath(scratchpath,"keepscratch","shared_scratch")))) == 73
end

@testset "projection" begin
  check_projection_logfiles(joinpath(scratchpath,"projection-coronal-local"))
  check_projection_logfiles(joinpath(scratchpath,"projection-coronal-cluster"))
  check_toplevel_projection_images(joinpath(scratchpath,"projection-coronal-local"))
  check_toplevel_projection_images(joinpath(scratchpath,"projection-coronal-cluster"))
  check_projection_images(scratchpath, ["projection-coronal-local","projection-coronal-cluster"], 5)
end

end
