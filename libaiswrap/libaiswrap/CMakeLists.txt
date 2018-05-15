##  ==========================================================================
##  Copyright (c) 2017-2018 Inkblot Software Limited
##
##  This Source Code Form is subject to the terms of the Mozilla Public
##  License, v. 2.0. If a copy of the MPL was not distributed with this
##  file, You can obtain one at http:##mozilla.org/MPL/2.0/.
##  ==========================================================================

cmake_minimum_required (VERSION 2.8)

include (ucm.cmake)

set (CMAKE_CXX_STANDARD 11)
set (BUILD_SHARED_LIBS FALSE)
## We need msvc to link to the static c++ stdlib, as dub/dmd does later
ucm_set_runtime (STATIC)

add_subdirectory (libais)

add_library (libaiswrap
    libaiswrap.cpp
)
target_link_libraries (libaiswrap
    PUBLIC ais
)
