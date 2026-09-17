# GDExtension HsOpenEXR: OpenEXR (BSD-3) dentro Godot per scrivere e leggere tutti i codec EXR.
# Si costruisce con tools/build_gdextension.sh (che prima compila OpenEXR statico in build/<piattaforma>/prefix).
cmake_minimum_required(VERSION 3.24)
project(hs_openexr LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# OpenEXR statico già installato in CMAKE_PREFIX_PATH (vedi lo script). Il suo config esporta un
# riferimento a `openjph` (HTJ2K, vendored) senza installarlo: lo script copia libopenjph.a nel prefix
# e qui lo si dichiara come target importato prima di find_package.
find_library(HS_OPENJPH_LIB openjph PATHS ${CMAKE_PREFIX_PATH}/lib NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH REQUIRED)
add_library(openjph STATIC IMPORTED)
set_target_properties(openjph PROPERTIES IMPORTED_LOCATION "${HS_OPENJPH_LIB}")
find_package(OpenEXR 3.4 CONFIG REQUIRED)

# godot-cpp v10 (master), agganciato a un commit preciso
include(FetchContent)
set(GODOTCPP_TARGET "template_release" CACHE STRING "")
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "")
set(GODOTCPP_DISABLE_EXCEPTIONS ON CACHE BOOL "") # solo per godot-cpp: qui le eccezioni di OpenEXR servono
FetchContent_Declare(godot-cpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG 507ed9d840c01a3c5b2a39af8bb4000bfac30bf5
    GIT_SHALLOW OFF)
FetchContent_MakeAvailable(godot-cpp)

add_library(hs_openexr SHARED
    src/hs_openexr.cpp
    src/register_types.cpp)
target_link_libraries(hs_openexr PRIVATE godot-cpp OpenEXR::OpenEXR)
target_compile_options(hs_openexr PRIVATE $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-fexceptions -fvisibility=hidden>)

# Nome del file come lo aspetta hs_openexr.gdextension
if(APPLE)
    set(HS_SUFFIX "macos.universal")
    set_target_properties(hs_openexr PROPERTIES PREFIX "lib" SUFFIX ".dylib")
elseif(WIN32)
    set(HS_SUFFIX "windows.x86_64")
    set_target_properties(hs_openexr PROPERTIES PREFIX "" SUFFIX ".dll")
else()
    set(HS_SUFFIX "linux.x86_64")
    set_target_properties(hs_openexr PROPERTIES PREFIX "lib" SUFFIX ".so")
endif()
set_target_properties(hs_openexr PROPERTIES
    OUTPUT_NAME "hs_openexr.${HS_SUFFIX}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out")
if(WIN32 AND NOT MSVC)
    # tutto statico dentro la DLL: niente libstdc++/winpthread da distribuire
    target_link_options(hs_openexr PRIVATE -static -static-libgcc -static-libstdc++ -s)
endif()
