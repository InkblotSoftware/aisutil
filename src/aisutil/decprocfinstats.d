//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.decprocfinstats;
import aisutil.decodeprocessdef, aisutil.filereading;
import std.range, std.algorithm;


//  ==========================================================================
//  == DecProcFinStats
//  ==   'Decode process finished' statistics provided to callers of
//  ==   executeDecodeProcess() to tell them what happend during the run
//  ==========================================================================


//  --------------------------------------------------------------------------
//  DecProcFinStats - stats summarising a completed decode run

struct DecProcFinStats {
    DecodeProcessDef procDef;  // what job did we run
    long inputLines;         // how many lines in read input
    long inputBytes;         // and how many bytes
    long parsedMsgs;         // num AIS messages parsed successfully
    long parsedMsgsWritten;  // num AIS messages passed filters and written out
    int  runTimeSecs;        // how long did the run take
}


//  --------------------------------------------------------------------------
//  Builder object, which collects info during the run process, tracks the
//  stats, and gives you a DecProcFinStats object when you call build()
//  at the end.
//  Initialise with the same ais file reader set you're decoding messages from.

struct DecProcFinStats_Builder {
    import std.datetime;
    private int _startTime;
    private DecProcFinStats _finStats;
    private const(AisFileReader)[] _readers;
    
    @disable this(this);
    // TODO add template constraint to this, so T must implement AisFileReader
    this(T)(DecodeProcessDef procDef, const(T)[] readers) {
        _finStats.procDef = procDef;
        _readers = readers.map!(r => cast(AisFileReader) r).array;
        _startTime = cast(int) Clock.currTime().toUnixTime();
    }

    // Get the total number of bytes read from input files so far
    long bytesRead () const {
        return _readers.map !(r => r.bytesRead).sum;
    }

    // Call this when a message passes all the filters and we write it out
    // (you should also have called notifyParsedMsg() on it before this)
    void notifyParsedMsgWritten () {++_finStats.parsedMsgsWritten;}

    DecProcFinStats build () {
        auto endTime = cast(int) Clock.currTime().toUnixTime();
        _finStats.runTimeSecs = endTime - _startTime;

        _finStats.inputLines = _readers.map!(r => r.linesRead).sum;
        _finStats.inputBytes = bytesRead ();
        _finStats.parsedMsgs = _readers.map!(r => r.aisMsgsRead).sum;
        
        return _finStats;
    }
}


//  --------------------------------------------------------------------------
//  Making a human-readable text summary of a DecProcFinStats, e.g. for the
//  run stats output file.

string textSummary (in ref DecProcFinStats stats) {
    import std.string;
    string res;

    res ~= "Completed run summary\n"
        ~  "=====================";
    
    res ~= "\n\n"
        ~  "Input files:\n";
    foreach (f; stats.procDef.inputFiles)
        res ~= format(" - %s\n", f);

    res ~= "\n\n"
        ~ "Output format:\n"
        ~ format(" - %s\n", stats.procDef.messageOutputFormat);

    res ~= "\n\n"
        ~ "Message filtering:\n"
        ~ format(" - simplified shiptype: %s\n", stats.procDef.filtSimShipType)
        ~ format(" - ship length category: %s\n", stats.procDef.filtShipLenCat)
        ~ format(" - geo bounds: lat (%s to %s), lon (%s to %s)\n",
                 stats.procDef.geoBounds.minLat, stats.procDef.geoBounds.maxLat,
                 stats.procDef.geoBounds.minLon, stats.procDef.geoBounds.maxLon);

    res ~= "\n\n"
        ~ "Message file output segregation:\n"
        ~ format(" - %s\n", stats.procDef.msgOutSegment);
    
    res ~= "\n\n"
        ~ "Run stats:\n"
        ~ format(" - total input bytes: %d\n", stats.inputBytes)
        ~ format(" - num input lines: %d\n", stats.inputLines)
        ~ format(" - num parsed AIS msgs: %d\n", stats.parsedMsgs)
        ~ format(" - num AIS msgs written after filters: %d\n",
                 stats.parsedMsgsWritten)
        ~ format(" - run time secs: %d\n", stats.runTimeSecs);

    return res;
}

