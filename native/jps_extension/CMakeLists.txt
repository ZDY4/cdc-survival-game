cmake_minimum_required(VERSION 3.21)

project(native_jps_extension LANGUAGES CXX)

include(FetchContent)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

FetchContent_Declare(
    godot_cpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG 9ae37ac8b9b14df5284dc3d4bf87e7d8b3327503
    GIT_SHALLOW TRUE
)

FetchContent_Declare(
    eigen
    GIT_REPOSITORY https://gitlab.com/libeigen/eigen.git
    GIT_TAG 3.4.0
    GIT_SHALLOW TRUE
)

FetchContent_Declare(
    jps3d
    GIT_REPOSITORY https://github.com/KumarRobotics/jps3d.git
    GIT_TAG ef65e36a8930395535e4683b1710e514b81d2f43
    GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(godot_cpp eigen jps3d)

set(TARGET_NAME native-jps-planner)
add_library(${TARGET_NAME} SHARED)

target_sources(
    ${TARGET_NAME}
    PRIVATE
        src/native_jps_planner.cpp
        src/register_types.cpp
        ${jps3d_SOURCE_DIR}/src/jps_planner/graph_search.cpp
        ${jps3d_SOURCE_DIR}/src/jps_planner/jps_planner.cpp
)

target_include_directories(
    ${TARGET_NAME}
    PRIVATE
        include
        third_party/compat
        ${jps3d_SOURCE_DIR}/include
        ${eigen_SOURCE_DIR}
)

target_link_libraries(${TARGET_NAME} PRIVATE godot-cpp)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin")

set_target_properties(
    ${TARGET_NAME}
    PROPERTIES
        CXX_VISIBILITY_PRESET ${GODOTCPP_SYMBOL_VISIBILITY}
        POSITION_INDEPENDENT_CODE ON
        BUILD_RPATH_USE_ORIGIN ON
        LINK_SEARCH_START_STATIC ON
        LINK_SEARCH_END_STATIC ON
        LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PREFIX "lib"
        OUTPUT_NAME "native_jps${GODOTCPP_SUFFIX}"
)

