${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/onechannel-local-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/threechannel-local-parameters.jl
ssh login1 "source /sge/current/default/common/settings.sh; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/onechannel-cluster-parameters.jl" &
ssh login1 "source /sge/current/default/common/settings.sh; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/threechannel-cluster-parameters.jl" &
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/linearinterp-parameters.jl
