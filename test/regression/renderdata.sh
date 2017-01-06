ssh login1 "source /sge/current/default/common/settings.sh; /groups/mousebrainmicro/mousebrainmicro/Software/barycentric3/src/render/src/render ${RENDER_PATH}/src/render/test/regression/987roiprod-parameters.jl" &
ssh login1 "source /sge/current/default/common/settings.sh; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/regression/987roidev-parameters.jl" &
