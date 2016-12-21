using Base.Test, Images

include(joinpath(ENV["RENDER_PATH"],"src/render/test/basictests.jl"))

function check_toplevel_images(basepath)
  img = load(joinpath(basepath,"default.0.tif"))
  rightanswer = zeros(UInt16,64);  rightanswer[36:end]=0xffff
  @test squeeze(maximum(raw(img),(1,2)),(1,2)) == rightanswer
  rightanswer = zeros(UInt16,640);  rightanswer[2:438]=0xffff
  @test squeeze(maximum(raw(img),(1,3)),(1,3)) == rightanswer
  rightanswer = zeros(UInt16,454);  rightanswer[[2:94;143:233]]=0xffff
  @test squeeze(maximum(raw(img),(2,3)),(2,3)) == rightanswer
end

scratchpath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledcube/scratch")

@testset "halffilledcube" begin

@testset "$v" for v in ["cpu", "avx", "localscratch"]
  check_logfiles( joinpath(scratchpath,"$v","logfile_scratch"), 64+1)
  check_toplevel_images(joinpath(scratchpath,"$v","results"))
end

@testset "cpu-vs-avx-vs-localscratch" begin
  check_images(scratchpath, ["cpu/results","avx/results","localscratch/results"], 1, 155, true)
  info("it is normal to have 7 avx images be off by 1 voxel each compared to cpu")
end

@testset "localscratch" begin
  log = readlines(joinpath(scratchpath,"localscratch","logfile_scratch","squatter1.log"))
  @test any(log.=="MANAGER: allocated RAM for 1 output tiles\n")
  @test any(line->contains(line,"to local_scratch"), log)
end

end
