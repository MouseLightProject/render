function check_logfiles(logfilepath, correct_nmergelogs)
  logfiles = readlines(`tar tvzf $logfilepath`)

  # all log files exist?
  @test any(x->endswith(x,"render.log"), logfiles)
  @test any(x->endswith(x,"director.log"), logfiles)
  #@test any(x->endswith(x,"monitor.log"), logfiles)
  @test any(x->endswith(x,"squatter1.log"), logfiles)
  @test sum(map(x->occursin("merge", x), logfiles)) == correct_nmergelogs

  # any errors reported in the log files?
  log = readlines(pipeline(`tar xvzfO $logfilepath`, stderr=devnull))
  for err in ["ERR","Err","WAR","War","Segmentation"]
    badlines = filter(x->occursin(err, x) && !occursin("can't delete", x), log)
    @test length(badlines)==0
    for badline in badlines
      println(badline)
    end
  end
end

function _load_tif_or_h5(filename, kind)
  if kind == :tif
    img = load(filename, false)
    return rawview(channelview(img))
  else
    img = h5read(filename,"/data")
    return dropdims(img, dims=1)
  end
end

function load_tif_or_h5(basepath)
  files = filter(x->occursin("default",x), readdir(basepath))
  kind = endswith(files[1],"tif") ? :tif : :h5
  img_raw = _load_tif_or_h5(joinpath(basepath,files[1]), kind)
  img = Array{UInt16}(undef, size(img_raw)...,length(files))
  img[:,:,:,1] = img_raw
  for ichannel=2:length(files)  
    img_raw = _load_tif_or_h5(joinpath(basepath,files[ichannel]), kind)
    img[:,:,:,ichannel] = img_raw
  end
  img
end

function check_images(scratchpath, testdirs, correct_nchannels, correct_nimages, black_and_white)
  # results directories recursively identical?
  hierarchies=[]
  for testdir in testdirs
    cd(joinpath(scratchpath,testdir,"results"))
    push!(hierarchies, collect(walkdir("."; topdown=true)))
    length(hierarchies)>1 || continue
    @test length(hierarchies[end-1])==length(hierarchies[end])
    length(hierarchies[end-1])==length(hierarchies[end]) || continue
    for (one,two) in zip(hierarchies[end-1],hierarchies[end])
      @test one[1]==two[1]
      @test one[2]==two[2]
      @test isempty(one[3])==isempty(two[3])
    end
  end

  # correct number of images, are they black & white, and identical?
  nimages=0
  shades=Set{UInt16}[]
  for (root, dirs, files) in hierarchies[1]
    isempty(files) && continue
    img = load_tif_or_h5(root)
    isempty(img) && continue
    nimages+=size(img,4)
    while length(shades)<size(img,4)
      push!(shades, Set{UInt16}())
    end
    imgs=Any[img]
    for ichannel=1:size(imgs[end],4)
      push!(shades[ichannel], unique(imgs[end][:,:,:,ichannel])...)
    end
    for testdir in testdirs[2:end]
      push!(imgs, load_tif_or_h5(joinpath(scratchpath,testdir,"results",root)))
      for ichannel=1:size(imgs[end],4)
        push!(shades[ichannel], unique(imgs[end][:,:,:,ichannel])...)
      end
      if length(imgs)>1
        @test imgs[end-1] == imgs[end]
        idx = findall(imgs[end-1] .!= imgs[end])
        if length(idx)>0
          largest_diff = round.(Int, 1/eps(eltype(imgs[end]))*maximum(abs.(
                convert(Array{Float64}, imgs[end-1][idx])-
                convert(Array{Float64}, imgs[end][idx]))))
          warn(joinpath(testdir,root,file)," off by ",length(idx),
                " voxel(s).  largest difference is ", largest_diff, " shade(s)")
        end
      end
    end
  end
  @test nimages == correct_nimages
  @test length(shades) == correct_nchannels
  if black_and_white
    @test all([length(x)<=2 for x in shades])
  else
    @test any([length(x)>2 for x in shades])
  end
  shades
end
