ssh login1 "source /misc/lsf/conf/profile.lsf; /groups/mousebrainmicro/mousebrainmicro/Software/barycentric3/src/render/src/render ${RENDER_PATH}/src/render/test/regression/987roiprod-parameters.jl" &
ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/regression/987roidev-parameters.jl" &
