cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Development builds need their own GTK application IDs. Otherwise GApplication
# forwards `flutter run` to an already-running installed release and the new
# process exits before Flutter can establish its debug connection.
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(RUNNER_APPLICATION_ID "${APPLICATION_ID}.debug")
elseif(CMAKE_BUILD_TYPE STREQUAL "Profile")
  set(RUNNER_APPLICATION_ID "${APPLICATION_ID}.profile")
else()
  set(RUNNER_APPLICATION_ID "${APPLICATION_ID}")
endif()
target_compile_definitions(
  ${BINARY_NAME} PRIVATE APPLICATION_ID="${RUNNER_APPLICATION_ID}"
)

# Add dependency libraries. Add any application-specific dependencies here.
# Keep GTK's transitive pkg-config libraries out of the executable's direct
# dependency list when the runner does not use them itself. This matters on
# NixOS, where a bare transitive dependency such as libz has no global /usr/lib
# location and otherwise cannot be found when Flutter launches the bundle.
target_link_options(${BINARY_NAME} PRIVATE "LINKER:--as-needed")
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
