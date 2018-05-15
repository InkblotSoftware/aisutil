//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

// Carries out a basic decode to a single NDJSON file output.
// Run summary is written to stdout as well as RUN_STATS.txt.

// USAGE:
//   ./aisnmea_to_ndjson OUTFILE_NAME.txt < FILE.nmea

import std.stdio, std.range, std.algorithm, std.exception;
import aisutil.decodeprocess, aisutil.decodeprocessdef, aisutil.decprocfinstats,
       aisutil.geo, aisutil.filewriting;

void main (string[] args) {
    enforce (args.length == 2);
    auto outfile = args[1];

    DecodeProcessDef procDef = { inputFiles: ["/dev/stdin"],
                                 messageOutputFormat: MessageOutputFormat.NDJSON,
                                 outputRootFile: outfile };

    auto stats = executeDecodeProcess (procDef);
    writeln (stats.textSummary ());
}
