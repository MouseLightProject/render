using Base.Test
using Images

include("../check_logfiles.jl")

@testset "halffilledcube" begin

@testset "$v" for v in ["cpu", "avx", "localscratch"]
  check_logfiles(
        joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch/$v"), 64+1)
end

@testset "cpu-vs-avx-vs-localscratch" begin
  basepath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch")

  # results directories recursively identical?
  cd(joinpath(basepath,"cpu"))
  cpu_hierarchy = collect(walkdir("results"))
  cd(joinpath(basepath,"avx"))
  avx_hierarchy = collect(walkdir("results"))
  cd(joinpath(basepath,"localscratch"))
  localscratch_hierarchy = collect(walkdir("results"))
  @test cpu_hierarchy == avx_hierarchy == localscratch_hierarchy

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
        localscratch_img = load(joinpath(basepath,"localscratch",root,file))
        push!(nshades, length(unique(localscratch_img)))
        @test cpu_img == avx_img ||
            warn(joinpath(root,file)," off by ",sum(cpu_img .!= avx_img)," voxel(s)")
        @test avx_img == localscratch_img ||
            warn(joinpath(root,file)," off by ",sum(avx_img .!= localscratch_img)," voxel(s)")
      end
    end
  end
  @test ntiffs == 155
  @test all(nshades.<=2)
  info("it is normal to have 7 avx images be off by 1 voxel each compared to cpu")

  log = readlines(joinpath(basepath,"localscratch","logfile_scratch","squatter1.log"))
  @test any(log.=="MANAGER: allocated RAM for 1 output tiles\n")
  @test any(line->contains(line,"to local_scratch"), log)
end

end
