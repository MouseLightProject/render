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
end

@testset "halffilledcube" begin

@testset "$v" for v in ["cpu", "avx"]
  nmergelogs = doit(
        joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch/$v"))
  @test nmergelogs == 64+1
end

@testset "cpu-vs-avx" begin
  basepath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch")

  # results directories recursively identical?
  cd(joinpath(basepath,"cpu"))
  cpu_hierarchy = collect(walkdir("results"))
  cd(joinpath(basepath,"avx"))
  avx_hierarchy = collect(walkdir("results"))
  @test cpu_hierarchy == avx_hierarchy

  # correct number of images, are they black & white, and identical?
  ntiffs=0
  nshades=Int[]
  for (root, dirs, files) in cpu_hierarchy
    for file in files
      if endswith(file,".tif")
        ntiffs+=1
        cpu_img = load(joinpath(basepath,"cpu",root,file))
        push!(nshades, length(unique(cpu_img)))
        avx_img = load(joinpath(basepath,"avx",root,file))
        push!(nshades, length(unique(avx_img)))
        ndiffvox = sum(cpu_img .!= avx_img)
        if ndiffvox>0
          warn(joinpath(root,file)," off by ",ndiffvox," voxel(s)")
        end
        @test cpu_img == avx_img
      end
    end
  end
  @test ntiffs == 64+8+2+1
  @test all(nshades.<=2)
end

end
