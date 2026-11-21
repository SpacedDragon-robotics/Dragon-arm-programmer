# Release build for the SpaceDragon Robot Programmer.
#
# This is only needed to produce a distributable .exe. Day-to-day editing of
# the app happens in Qt Design Studio via ../DragonArmStudio.qmlproject and
# needs no compiler at all.
#
# Configure with the Qt kit you want to ship against, for example:
#
#   cmake -S packaging -B build -G Ninja ^
#         -DCMAKE_BUILD_TYPE=Release ^
#         -DCMAKE_PREFIX_PATH="<Qt>/6.x.y/mingw_64"
#   cmake --build build
#
# No Qt or toolchain path is hard-coded here, so the project builds on any
# machine with a Qt 6.5+ kit.

cmake_minimum_required(VERSION 3.21)

project(SpaceDragon VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_standard_project_setup()

# The QML lives one level up, beside this folder.
set(APP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")

qt_add_executable(SpaceDragon WIN32
    main.cpp
)

target_compile_definitions(SpaceDragon PRIVATE
    SPACEDRAGON_VERSION="${PROJECT_VERSION}"
)

# ---------------------------------------------------------------------------
# Embed the application
#
# Everything the engine loads at runtime is compiled into the binary, keeping
# the released app a single executable. Globbing is deliberate: adding a new
# .qml file should not mean editing this list. Re-run cmake after adding files.
# ---------------------------------------------------------------------------
file(GLOB_RECURSE APP_RESOURCES
    "${APP_ROOT}/content/*.qml"
    "${APP_ROOT}/content/*.js"
    "${APP_ROOT}/content/*.png"
    "${APP_ROOT}/content/*.jpg"
    "${APP_ROOT}/content/*.jpeg"
    "${APP_ROOT}/content/*.svg"
    "${APP_ROOT}/content/*.ttf"
    "${APP_ROOT}/content/*.otf"
    "${APP_ROOT}/content/fonts/OFL.txt"   # the font licence must travel with the font
    "${APP_ROOT}/content/*.mesh"      # 3D view rigs (tools/export_3d_model.ps1)
    "${APP_ROOT}/imports/*.qml"
    "${APP_ROOT}/imports/*.js"
    "${APP_ROOT}/imports/*/qmldir"
)

list(LENGTH APP_RESOURCES APP_RESOURCE_COUNT)
message(STATUS "SpaceDragon: embedding ${APP_RESOURCE_COUNT} application files")

if(APP_RESOURCE_COUNT EQUAL 0)
    message(FATAL_ERROR "No application files found under ${APP_ROOT}. "
                        "Run cmake from the project root, not from inside packaging/.")
endif()

# BASE keeps the resource paths identical to the on-disk layout, so
# qrc:/content/App.qml and :/imports resolve exactly as they do in Design Studio.
qt_add_resources(SpaceDragon "spacedragon_app"
    PREFIX "/"
    BASE "${APP_ROOT}"
    FILES ${APP_RESOURCES}
)

target_link_libraries(SpaceDragon PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

# Windows: application icon and file metadata.
if(WIN32)
    set(APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/spacedragon.ico")
    if(EXISTS "${APP_ICON}")
        set_target_properties(SpaceDragon PROPERTIES
            QT_TARGET_WINDOWS_RC_FILE ""
        )
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/appicon.rc.in"
            "${CMAKE_CURRENT_BINARY_DIR}/appicon.rc"
            @ONLY)
        target_sources(SpaceDragon PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/appicon.rc")
    endif()
endif()

install(TARGETS SpaceDragon
    RUNTIME DESTINATION .
    BUNDLE  DESTINATION .
)
