# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(yolo_label_tool LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "yolo_label_tool")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Runtime files are copied by the custom install script below. Keeping INSTALL
# out of the default Visual Studio build avoids duplicate runtime copy steps.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 0)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")
set(RUNTIME_BUNDLE_DIR "${CMAKE_CURRENT_BINARY_DIR}/runner/\${CMAKE_INSTALL_CONFIG_NAME}")

# Flutter builds the INSTALL target on Windows. Use checked cmake -E copy
# commands instead of install(FILES), because file(INSTALL) can fail on locked
# Windows files while trying to reset permissions.
set(RUNTIME_INSTALL_CODE [=[
function(runtime_copy)
  execute_process(COMMAND ${ARGV} RESULT_VARIABLE result)
  if(NOT result EQUAL 0)
    string(REPLACE ";" " " command_line "${ARGV}")
    message(FATAL_ERROR "Runtime copy failed: ${command_line}")
  endif()
endfunction()

message(STATUS "Copying runtime files without permission reset.")
file(MAKE_DIRECTORY "@RUNTIME_BUNDLE_DIR@/data")
runtime_copy("@CMAKE_COMMAND@" -E copy_if_different
  "@FLUTTER_ICU_DATA_FILE@"
  "@RUNTIME_BUNDLE_DIR@/data/icudtl.dat")
runtime_copy("@CMAKE_COMMAND@" -E copy_if_different
  "@FLUTTER_LIBRARY@"
  "@RUNTIME_BUNDLE_DIR@/flutter_windows.dll")
]=])
string(CONFIGURE "${RUNTIME_INSTALL_CODE}" RUNTIME_INSTALL_CODE @ONLY)

if(PLUGIN_BUNDLED_LIBRARIES)
  foreach(PLUGIN_BUNDLED_LIBRARY IN LISTS PLUGIN_BUNDLED_LIBRARIES)
    string(APPEND RUNTIME_INSTALL_CODE
      "set(plugin_source \"${PLUGIN_BUNDLED_LIBRARY}\")\n"
      "get_filename_component(plugin_name \"\${plugin_source}\" NAME)\n"
      "runtime_copy(\"${CMAKE_COMMAND}\" -E copy_if_different \"\${plugin_source}\" \"${RUNTIME_BUNDLE_DIR}/\${plugin_name}\")\n")
  endforeach()
endif()

set(RUST_BRIDGE_RELEASE_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../../target/release/yolo_label_bridge.dll")
set(RUST_BRIDGE_DEBUG_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../../target/debug/yolo_label_bridge.dll")
string(APPEND RUNTIME_INSTALL_CODE "
if(EXISTS \"${RUST_BRIDGE_RELEASE_DLL}\")
  runtime_copy(\"${CMAKE_COMMAND}\" -E copy_if_different \"${RUST_BRIDGE_RELEASE_DLL}\" \"${RUNTIME_BUNDLE_DIR}/yolo_label_bridge.dll\")
elseif(EXISTS \"${RUST_BRIDGE_DEBUG_DLL}\")
  runtime_copy(\"${CMAKE_COMMAND}\" -E copy_if_different \"${RUST_BRIDGE_DEBUG_DLL}\" \"${RUNTIME_BUNDLE_DIR}/yolo_label_bridge.dll\")
endif()
")

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
string(APPEND RUNTIME_INSTALL_CODE "
if(EXISTS \"${NATIVE_ASSETS_DIR}\")
  runtime_copy(\"${CMAKE_COMMAND}\" -E copy_directory \"${NATIVE_ASSETS_DIR}\" \"${RUNTIME_BUNDLE_DIR}\")
endif()
")

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
string(APPEND RUNTIME_INSTALL_CODE "
runtime_copy(\"${CMAKE_COMMAND}\" -E rm -rf \"${RUNTIME_BUNDLE_DIR}/data/${FLUTTER_ASSET_DIR_NAME}\")
runtime_copy(\"${CMAKE_COMMAND}\" -E copy_directory \"${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}\" \"${RUNTIME_BUNDLE_DIR}/data/${FLUTTER_ASSET_DIR_NAME}\")
")

# Install the AOT library on non-Debug builds only.
string(APPEND RUNTIME_INSTALL_CODE "
if(EXISTS \"${AOT_LIBRARY}\")
  runtime_copy(\"${CMAKE_COMMAND}\" -E copy_if_different \"${AOT_LIBRARY}\" \"${RUNTIME_BUNDLE_DIR}/data/app.so\")
endif()
")

install(CODE "${RUNTIME_INSTALL_CODE}")
