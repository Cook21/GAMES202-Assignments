cmake_minimum_required (VERSION 3.2)
project (Denoise)

set (CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)
########################################

include_directories(
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/src/ext
)

file(GLOB SOURCE_FILE
    ${CMAKE_SOURCE_DIR}/src/*.h
    ${CMAKE_SOURCE_DIR}/src/*.cpp
    ${CMAKE_SOURCE_DIR}/src/util/*.h
    ${CMAKE_SOURCE_DIR}/src/util/*.cpp
    ${CMAKE_SOURCE_DIR}/src/ext/*/*.h
)

# Sort the file into different folders
foreach(_source_file IN ITEMS ${SOURCE_FILE})
    get_filename_component(_source_path "${_source_file}" PATH)
    string(REPLACE "${CMAKE_SOURCE_DIR}" "" _group_path "${_source_path}")
    string(REPLACE "/" "\\" _group_path "${_group_path}")
    source_group("${_group_path}" FILES "${_source_file}")
endforeach()
add_executable(Denoise ${SOURCE_FILE})
########################################

# OpenMP
FIND_PACKAGE(OpenMP REQUIRED)
if(OPENMP_FOUND)
    message("OPENMP FOUND")
    target_link_libraries(Denoise PRIVATE OpenMP::OpenMP_CXX)
endif()
########################################

