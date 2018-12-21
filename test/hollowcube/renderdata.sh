ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/onechannel-cluster-parameters.jl" &
ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/threechannel-cluster-parameters.jl" &
ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/nslots-parameters.jl" &
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/onechannel-local-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/threechannel-local-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/linearinterp-onechannel-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/linearinterp-threechannel-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/linearinterp-threechannel-cpu-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/keepscratch-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/onechannel-hdf5-parameters.jl
${RENDER_PATH}/src/render/src/render ${RENDER_PATH}/src/render/test/hollowcube/threechannel-hdf5-parameters.jl
ssh login1 "source /misc/lsf/conf/profile.lsf; ${RENDER_PATH}/src/render/src/project ${RENDER_PATH}/src/render/test/hollowcube/projection-coronal-cluster-parameters.jl" &
${RENDER_PATH}/src/render/src/project ${RENDER_PATH}/src/render/test/hollowcube/projection-coronal-local-parameters.jl
