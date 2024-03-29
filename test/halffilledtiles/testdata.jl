using Test

include(joinpath(ENV["RENDER_PATH"],"src/render/test/basictests.jl"))

function check_toplevel_images(basepath)
  img = load_tif_or_h5(basepath)
  rightanswer = zeros(UInt16,64);  rightanswer[36:end] .= 0xffff
  @test all(dropdims(maximum(img, dims=(1,2)), dims=(1,2)) .== rightanswer)
  rightanswer = zeros(UInt16,454);  rightanswer[[2:94;143:233]] .= 0xffff
  @test all(dropdims(maximum(img, dims=(2,3)), dims=(2,3)) .== rightanswer)
  rightanswer = zeros(UInt16,640);  rightanswer[2:438] .= 0xffff
  @test all(dropdims(maximum(img, dims=(1,3)), dims=(1,3)) .== rightanswer)
end

scratchpath = joinpath(ENV["RENDER_PATH"],"src/render/test/halffilledtiles/scratch")

@testset "halffilledtiles" begin

@testset "$v" for v in ["cpu", "avx", "avx-cluster", "localscratch", "hdf5"]
  check_logfiles( joinpath(scratchpath,"$v","results","logs.tar.gz"), 512+1)
  check_toplevel_images(joinpath(scratchpath,"$v","results"))
end

@testset "cpu-vs-avx-vs-localscratch-hdf5" begin
  check_images(scratchpath, ["cpu","avx","avx-cluster","localscratch","hdf5"], 1, 155, true)
end

@testset "localscratch" begin
  logfilepath = joinpath(scratchpath,"localscratch","results","logs.tar.gz")
  log = readlines(`tar xvzfO $logfilepath squatter1.log`)
  @test any(log.=="[ Info: MANAGER: allocated RAM for 1 output tiles")
  @test any(line->occursin("to local_scratch", line), log)
end

end
