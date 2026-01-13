cmake_minimum_required(VERSION 3.10)

# Configure the build configuration.
add_definitions(-DAPPLICATION_ID="com.typesync.app")

# Add required dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Define the application target.
add_executable(${BINARY_NAME}
  "../main.cc"
  "../my_application.cc"
)

# Apply standard settings.
apply_standard_settings(${BINARY_NAME})

# Add dependency libraries and include directories.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Include Flutter headers.
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}"
)

