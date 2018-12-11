ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledcube/avx-cluster-parameters.jl" &
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledcube/cpu-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledcube/avx-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledcube/localscratch-parameters.jl
