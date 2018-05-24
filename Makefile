##  ==========================================================================
##  Copyright (c) 2017-2018 Inkblot Software Limited
##
##  This Source Code Form is subject to the terms of the Mozilla Public
##  License, v. 2.0. If a copy of the MPL was not distributed with this
##  file, You can obtain one at http://mozilla.org/MPL/2.0/.
##  ==========================================================================

### Driver for dub on Linux
###
###   NB this doesn't call the compiler when you change files in libaiswrap,
###   you have do that manually. You'll also want to `dub clean` to be sure.

SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:


##  ---------------------------------------------------------------------
##  Source files / libraries

D_SRC := $(shell find src/ -name "*.d")           \
         src/aisutil/worldMap1080x540_4.png

LAW_LIB := libaiswrap/lin_build/liblibaiswrap.a


##  ---------------------------------------------------------------------
##  Targets

all: bin/aisutil  \
     bin/aisnmea_to_ndjson  \
     bin/mcaais_to_ndjson

bin/aisutil: $(D_SRC) $(LAW_LIB) app_src/aisutil_gui.d
	dub build --config=aisutil --build=release

bin/aisnmea_to_ndjson: $(D_SRC) $(LAW_LIB) app_src/aisnmea_to_ndjson.d
	dub build --config=aisnmea_to_ndjson --build=release

bin/mcaais_to_ndjson: $(D_SRC) $(LAW_LIB) app_src/mcaais_to_ndjson.d
	dub build --config=mcaais_to_ndjson --build=release
