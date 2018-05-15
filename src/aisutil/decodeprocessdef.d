//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.decodeprocessdef;
import std.range, std.algorithm;
import aisutil.geo, aisutil.filewriting;


//  ==========================================================================
//  == Definition of one decode process the user want's the program to carry out
//  ==   -> struct DecodeProcessDef
//  ==
//  ==   Passed to the executeDecodeProcess() work function.
//  ==
//  ==   Use the other types in this file to create one of these objects.
//  ==========================================================================


//  --------------------------------------------------------------------------
//  Main definition struct

struct DecodeProcessDef {
    immutable(string)[] inputFiles;

    // Path to the 'root' (status text) file we save to - everything else is
    // based on this path but with a name suffix
    string outputRootFile;

    // Geo bounds to include for positional messages.
    // Defaults to whole world (but not outside it, nb ais null pos is 91,181)
    GeoBounds geoBounds = GeoBounds.withWorld();

    // Does the user want NDJSON or CSV output?
    MessageOutputFormat messageOutputFormat;

    // How does the user want written-out messages segmented across files?
    MessageOutputSegmentation msgOutSegment;

    // What filtering does the user want?
    MmsiFilterSimpleShiptype filtSimShipType;
    MmsiFilterShipLenCat     filtShipLenCat;
    
    void addInputFile(in string filePath) {
        inputFiles ~= filePath.dup;
        inputFiles = inputFiles.dup.sort.uniq.array.idup;
    }
}


//  --------------------------------------------------------------------------
//  Types used in main defintion struct

// Segmenting output across files
enum MessageOutputSegmentation {
    AllInOne,
    VesselCategories,
    ShipLenCat,
    TimestampDay,
}

// Filtering mmsis by broadcast simple shiptype
enum MmsiFilterSimpleShiptype {
    DontFilter,
    OnlyFishing,
    OnlyCargo,
    OnlyTanker,
}

// Filtering mmsis by broadcast simple shiplen
enum MmsiFilterShipLenCat {
    DontFilter,
    OnlyMetres0to5,
    OnlyMetres5to20,
    OnlyMetresAbove20,
}


//  --------------------------------------------------------------------------
//  Helpers/accessors

ulong totalBytesInInput (DecodeProcessDef procDef) {
    import std.file;
    return procDef.inputFiles.map!getSize.sum();
}
