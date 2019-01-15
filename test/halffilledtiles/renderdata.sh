ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledtiles/avx-cluster-parameters.jl" &
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledtiles/cpu-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledtiles/avx-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledtiles/localscratch-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/halffilledtiles/hdf5-parameters.jl
