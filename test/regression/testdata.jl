using Test, Images

include(joinpath(ENV["RENDER_PATH"],"src/render/test/basictests.jl"))

logfile_scratch_path="/groups/mousebrainmicro/mousebrainmicro/scratch/arthurb"
destination_path="/nrs/mouselight/arthurb"

@testset "regression" begin

@testset "logfiles" begin
  check_logfiles(joinpath(logfile_scratch_path,"987roiprod"), 2*64+2)
  check_logfiles(joinpath(logfile_scratch_path,"987roidev"), 64+1)
end

@testset "images" begin
  dev=load(joinpath(destination_path,"987roidev/default.0.tif"))
  prod=load(joinpath(destination_path,"987roiprod/default.0.tif"))
  @test sum(dev)!=0
  @test sum(prod)!=0
  @test sum(dev)==sum(prod)
  check_images(destination_path, ["987roiprod","987roidev"], 2, 64+8+1, false)
end

end
