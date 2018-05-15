##  ==========================================================================
##  Copyright (c) 2017-2018 Inkblot Software Limited
##
##  This Source Code Form is subject to the terms of the Mozilla Public
##  License, v. 2.0. If a copy of the MPL was not distributed with this
##  file, You can obtain one at http:##mozilla.org/MPL/2.0/.
##  ==========================================================================

SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:

## Default target
pass:


##  --------------------------------------------------------------------------
##  Input files and programs

SRCAIS := raw_data.nmea

DECODEPROG := ../../bin/aisnmea_to_ndjson


##  --------------------------------------------------------------------------
##  Top-level test runner

.PHONY: run-tests
run-tests: sot/$(SRCAIS).ndjson decode_output/MESSAGES.ndjson
	python ../check_ndjson_files_same.py $^ 2>&1


##  --------------------------------------------------------------------------
##  'Source of truth' decoding

sot/$(SRCAIS).ndjson: ../sot_decode_nmea.py $(SRCAIS)
	time           \
	cat $(SRCAIS)  \
	| python2 $<   \
	> $@


##  --------------------------------------------------------------------------
##  Actual program output generation (we test this against the sot)

decode_output/MESSAGES.ndjson: $(DECODEPROG) $(SRCAIS)
	cd $(dir $@) &&  \
	time ../$(DECODEPROG) MESSAGES.txt < ../$(SRCAIS)


##  --------------------------------------------------------------------------
##  Utils

clean:
	rm -f decode_output/*       \
              sot/$(SRCAIS).ndjson
