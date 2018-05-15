//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.decprocfinstats;
import aisutil.decodeprocessdef;


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
//  Builder object, which takes a stream of notifications of lines read, lines
//  parsed successfully and messages written (i.e. passed filters) and tracks
//  the stats, allowing you to build to a DecProcFinStats at the end.

struct DecProcFinStats_Builder {
    import std.datetime;
    private int _startTime;
    private DecProcFinStats _finStats;

    @disable this(this);
    this(DecodeProcessDef procDef) {
        _finStats.procDef = procDef;
        _startTime = cast(int) Clock.currTime().toUnixTime();
    }

    // Call this every time you read an input line
    import std.traits;
    void notifyInputLine(T) (in T line) if(isSomeString!T) {
        ++_finStats.inputLines;
        _finStats.inputBytes += line.length + 1;  // TODO +2 if \r
    }

    // Call this when you parse a message successfully
    void notifyParsedMsg () {++_finStats.parsedMsgs;}

    // Call this when a message passes all the filters and we write it out
    // (you should also have called notifyParsedMsg() on it before this)
    void notifyParsedMsgWritten () {++_finStats.parsedMsgsWritten;}

    DecProcFinStats build () {
        auto endTime = cast(int) Clock.currTime().toUnixTime();
        _finStats.runTimeSecs = endTime - _startTime;
        return _finStats;
    }
}


//  --------------------------------------------------------------------------
//  Making a human-readable text summary of a DecProcFinStats, e.g. for the
//  run stats output file.

string textSummary (in ref DecProcFinStats stats) {
    import std.string;
    string res;

    res ~= "PROCESSED INPUT FILES:\n";
    foreach (f; stats.procDef.inputFiles)
        res ~= format(" - %s\n", f);

    res ~= "\n\n"
        ~ "OUTPUT FORMAT:\n"
        ~ format(" -> %s\n", stats.procDef.messageOutputFormat);

    res ~= "\n\n"
        ~ "FILTERING:\n"
        ~ format(" - simplified shiptype: %s\n", stats.procDef.filtSimShipType)
        ~ format(" - ship length category: %s\n", stats.procDef.filtShipLenCat)
        ~ format(" - geo bounds: %s\n", stats.procDef.geoBounds);

    res ~= "\n\n"
        ~ "MESSAGE FILE OUTPUT SEGMENTATION:\n"
        ~ format(" -> %s\n", stats.procDef.msgOutSegment);
    
    res ~= "\n\n"
        ~ "RUN STATS:\n"
        ~ format(" - total input bytes: %d\n", stats.inputBytes)
        ~ format(" - num input lines: %d\n", stats.inputLines)
        ~ format(" - num parsed AIS msgs: %d\n", stats.parsedMsgs)
        ~ format(" - num AIS msgs written after filters: %d\n", stats.parsedMsgsWritten)
        ~ format(" - run time secs: %d\n", stats.runTimeSecs);

    return res;
}

