function check_logfiles(logfilepath, correct_nmergelogs)
  logfiles = readdir(logfilepath)

  # all log files exist?
  @test any(logfiles.=="render.log")
  @test any(logfiles.=="director.log")
  @test any(logfiles.=="monitor.log")
  @test any(file->startswith(file,"squatter"), logfiles)
  @test sum(map(x->startswith(x, "merge"), logfiles)) == correct_nmergelogs

  # any errors reported in the log files?
  for logfile in logfiles
    log = read(joinpath(logfilepath,logfile))
    @test !contains(String(log), "ERR")
    @test !contains(String(log), "WAR")
    @test !contains(String(log), "Segmentation")
  end
end

function check_images(scratchpath, testdirs, correct_nchannels, correct_ntiffs, black_and_white)
  # results directories recursively identical?
  hierarchies=[]
  for testdir in testdirs
    cd(joinpath(scratchpath,testdir))
    push!(hierarchies, collect(walkdir(".")))
    length(hierarchies)>1 && @test hierarchies[end-1]==hierarchies[end]
  end

  # correct number of images, are they black & white, and identical?
  ntiffs=0
  shades=Vector{Vector{Float32}}[]
  for (root, dirs, files) in hierarchies[1]
    for file in files
      if endswith(file,".tif")
        ntiffs+=1
        channel = parse(Int, split(file,'.')[end-1])
        while length(shades)<channel+1
          push!(shades,[])
        end
        imgs=[]
        for testdir in testdirs
          push!(imgs, load(joinpath(scratchpath,testdir,root,file)))
          push!(shades[1+channel], unique(imgs[end]))
          if length(imgs)>1
            @test imgs[end-1] == imgs[end]
            idx = find(imgs[end-1] .!= imgs[end])
            if length(idx)>0
              largest_diff = round(Int, 1/eps(eltype(imgs[end]))*maximum(abs(
                    convert(Array{Float64}, imgs[end-1][idx])-convert(Array{Float64}, imgs[end][idx]))))
              warn(joinpath(testdir,root,file)," off by ",length(idx)," voxel(s).  largest difference is ", largest_diff, " shade(s)")
            end
          end
        end
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
