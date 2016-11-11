using Base.Test, Images

include(joinpath(ENV["RENDER_PATH"],"src/render/test/basictests.jl"))

@testset "halffilledcube" begin

@testset "$v" for v in ["cpu", "avx", "localscratch"]
  check_logfiles(
        joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch/$v"), 64+1)
end

@testset "cpu-vs-avx-vs-localscratch" begin
  scratchpath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch")
  check_images(scratchpath, ["cpu","avx","localscratch"], 1, 155, true)
  info("it is normal to have 7 avx images be off by 1 voxel each compared to cpu")

  log = readlines(joinpath(scratchpath,"localscratch","logfile_scratch","squatter1.log"))
  @test any(log.=="MANAGER: allocated RAM for 1 output tiles\n")
  @test any(line->contains(line,"to local_scratch"), log)
end

end
