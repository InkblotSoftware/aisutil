//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.decodeprocess;
import std.range, std.algorithm, std.stdio, std.typecons, std.conv, std.variant,
       std.exception;
import aisutil.filewriting, aisutil.mmsistats, aisutil.ais, 
       aisutil.decodeprocessdef, aisutil.geo, aisutil.decprocfinstats,
       aisutil.geoheatmap, aisutil.dlibaiswrap, aisutil.simpleshiptypes,
       aisutil.shiplengths, aisutil.daisnmea, aisutil.backlog, 
       aisutil.aisnmeagrouping;


//  ==========================================================================
//  == The main decode process; the purpose of this software
//  ==   -> executeDecodeProcess() is the main entrypoint
//  ==
//  ==   NB there's no global state in this module, except for writing to
//  ==   the output files
//  ==========================================================================


//  --------------------------------------------------------------------------
//  Updates sent from a running process to the caller
//    NB DecodeProcessFinStats is sent when it finishes

struct DecodeProcessCurRunningStats {
    ulong bytesProcessed;     // How many have we read/processed from input files?
    ulong totalBytesInInput;  // How many in total were there to to do?
}


//  --------------------------------------------------------------------------
//  Variant-handling helper for MsgFileWriter classes
//    Helper for executeDecodeProcess()

void writeAnyAisMsg (ref Unique!MsgFileWriter msgWriter,
                     AnyAisMsg msg, PossTimestamp possTS, MmsiStats stats) {
    msg.visit!(
        (AisMsg1n2n3 m) => msgWriter.writeMsg (m, possTS, stats),
        (AisMsg5     m) => msgWriter.writeMsg (m, possTS, stats),
        (AisMsg18    m) => msgWriter.writeMsg (m, possTS, stats),
        (AisMsg19    m) => msgWriter.writeMsg (m, possTS, stats),
        (AisMsg24    m) => msgWriter.writeMsg (m, possTS, stats),
        (AisMsg27    m) => msgWriter.writeMsg (m, possTS, stats)
    )();
}
void writeAnyAisMsg_noStats (ref Unique!MsgFileWriter msgWriter,
                             AnyAisMsg msg, PossTimestamp possTS) {
    msg.visit!(
        (AisMsg1n2n3 m) => msgWriter.writeMsg_noStats (m, possTS),
        (AisMsg5     m) => msgWriter.writeMsg_noStats (m, possTS),
        (AisMsg18    m) => msgWriter.writeMsg_noStats (m, possTS),
        (AisMsg19    m) => msgWriter.writeMsg_noStats (m, possTS),
        (AisMsg24    m) => msgWriter.writeMsg_noStats (m, possTS),
        (AisMsg27    m) => msgWriter.writeMsg_noStats (m, possTS)
    )();
}


//  --------------------------------------------------------------------------
//  Queryable set of per-MMSI filters
//    Helper for executeDecodeProcess()
//  
//    Init with the process def the user wants to perform, and then call
//    canJudge() on an MMSI's currently-known-stat-dats to see whether
//    you can yet judge it against the procdef's filters, and then shouldWrite()
//    to see whether those filters tell you to write it to the output files.

private struct MmsiFilterSet {
    @disable this(this);

    private MmsiFilterSimpleShiptype _typeFilt;
    private MmsiFilterShipLenCat     _lenFilt;
    
    this (DecodeProcessDef procDef) {
        _typeFilt = procDef.filtSimShipType; _lenFilt = procDef.filtShipLenCat; }

    bool canJudge (in ref MmsiStats stats) const {
        return canJudge_onType (stats) && canJudge_onLen (stats); }

    bool shouldWrite (in ref MmsiStats stats) const {
        enforce (canJudge (stats));
        return shouldWrite_onType (stats) && shouldWrite_onLen (stats); }

    // Internal
    
    private bool canJudge_onType (in ref MmsiStats stats) const {
        final switch (_typeFilt) with (MmsiFilterSimpleShiptype) {
            case DontFilter:  return true;
            case OnlyFishing: return stats.hasShiptype;
            case OnlyCargo:   return stats.hasShiptype;
            case OnlyTanker:  return stats.hasShiptype; }
    }
    private bool canJudge_onLen (in ref MmsiStats stats) const {
        final switch (_lenFilt) with (MmsiFilterShipLenCat) {
            case DontFilter:        return true;
            case OnlyMetres0to5:    return stats.hasShiplen;
            case OnlyMetres5to20:   return stats.hasShiplen;
            case OnlyMetresAbove20: return stats.hasShiplen; }
    }

    private bool shouldWrite_onType (in ref MmsiStats stats) const {
        // Called lazily, in case stats lacks shiptype on DontFilter case
        SimpleShiptype sst() {return stats.shiptype.simplifyShiptype;}
        
        final switch (_typeFilt) with (MmsiFilterSimpleShiptype) {
            case DontFilter:  return true;
            case OnlyFishing: return sst() == SimpleShiptype.Fishing;
            case OnlyCargo:   return sst() == SimpleShiptype.Cargo;
            case OnlyTanker:  return sst() == SimpleShiptype.Tanker; }
    }
    private bool shouldWrite_onLen (in ref MmsiStats stats) const {
        // Called lazily, in case stats lacks shiplen on DontFilter case
        ShipLenCat lencat() {return stats.shiplen.shipLenCatForLen;}

        final switch (_lenFilt) with (MmsiFilterShipLenCat) {
            case DontFilter: return true;
            case OnlyMetres0to5:    return lencat() == ShipLenCat.Metres0to5;
            case OnlyMetres5to20:   return lencat() == ShipLenCat.Metres5to20;
            case OnlyMetresAbove20: return lencat() == ShipLenCat.MetresAbove20; }
    }
}

unittest {
    DecodeProcessDef pdNoFilt =
                         { filtSimShipType: MmsiFilterSimpleShiptype.DontFilter,
                           filtShipLenCat:  MmsiFilterShipLenCat.DontFilter };
    
    DecodeProcessDef pdTanker =
                         { filtSimShipType: MmsiFilterSimpleShiptype.OnlyTanker,
                           filtShipLenCat:  MmsiFilterShipLenCat.DontFilter };
    
    DecodeProcessDef pdFishing =
                         { filtSimShipType: MmsiFilterSimpleShiptype.OnlyFishing,
                           filtShipLenCat:  MmsiFilterShipLenCat.DontFilter };

    DecodeProcessDef pdShortLen =
                         { filtSimShipType: MmsiFilterSimpleShiptype.DontFilter,
                           filtShipLenCat:   MmsiFilterShipLenCat.OnlyMetres0to5 };

    DecodeProcessDef pdLongLen =
                         { filtSimShipType: MmsiFilterSimpleShiptype.DontFilter,
                           filtShipLenCat:  MmsiFilterShipLenCat.OnlyMetresAbove20 };

    DecodeProcessDef pdLongLenTank =
                         { filtSimShipType: MmsiFilterSimpleShiptype.OnlyTanker,
                           filtShipLenCat:  MmsiFilterShipLenCat.OnlyMetresAbove20 };

    immutable mmsi = 12345;
    {
        auto ms = MmsiStats (mmsi);
        
        assert (MmsiFilterSet (pdNoFilt).canJudge (ms));
        assert (MmsiFilterSet (pdNoFilt).shouldWrite (ms));

        assert (! MmsiFilterSet (pdTanker).canJudge (ms));
        assert (! MmsiFilterSet (pdFishing).canJudge (ms));
        
        assert (! MmsiFilterSet (pdShortLen).canJudge (ms));
        assert (! MmsiFilterSet (pdLongLen).canJudge (ms));
        
        assert (! MmsiFilterSet (pdLongLenTank).canJudge (ms));
    }

    {
        auto ms = MmsiStats (mmsi);
        ms.shiptype = 30;  // fishing
        
        assert (MmsiFilterSet (pdNoFilt).canJudge (ms));
        assert (MmsiFilterSet (pdNoFilt).shouldWrite (ms));

        assert (  MmsiFilterSet (pdTanker).canJudge (ms));
        assert (! MmsiFilterSet (pdTanker).shouldWrite (ms));
        
        assert (  MmsiFilterSet (pdFishing).canJudge (ms));
        assert (  MmsiFilterSet (pdFishing).shouldWrite (ms));
        
        assert (! MmsiFilterSet (pdShortLen).canJudge (ms));
        assert (! MmsiFilterSet (pdLongLen).canJudge (ms));
        
        assert (! MmsiFilterSet (pdLongLenTank).canJudge (ms));
    }

    {
        auto ms = MmsiStats (mmsi);
        ms.shiptype = 30;  // fishing
        ms.shiplen = 3;  // short
        
        assert (MmsiFilterSet (pdNoFilt).canJudge (ms));
        assert (MmsiFilterSet (pdNoFilt).shouldWrite (ms));

        assert (  MmsiFilterSet (pdTanker).canJudge (ms));
        assert (! MmsiFilterSet (pdTanker).shouldWrite (ms));
        
        assert (  MmsiFilterSet (pdFishing).canJudge (ms));
        assert (  MmsiFilterSet (pdFishing).shouldWrite (ms));
        
        assert (  MmsiFilterSet (pdShortLen).canJudge (ms));
        assert (  MmsiFilterSet (pdShortLen).shouldWrite (ms));
        
        assert (  MmsiFilterSet (pdLongLen).canJudge (ms));
        assert (! MmsiFilterSet (pdLongLen).shouldWrite (ms));
        
        assert (  MmsiFilterSet (pdLongLenTank).canJudge (ms));
        assert (! MmsiFilterSet (pdLongLenTank).shouldWrite (ms));
    }
}


//  --------------------------------------------------------------------------
//  GeoBounds helper extension
//    Helper for executeDecodeProcess()

// As contains() if msg has lat/lon; true always otherwise
private bool containsOrIsNotPositional(T) (in ref GeoBounds bounds, in ref T obj)
    if(isAisMsg!T)
{
    static if (isPositional!T) {
        return bounds.contains (obj);
    } else {
        return true;
    }
}
private bool containsOrIsNotPositional (in ref GeoBounds bounds, in ref AnyAisMsg msg) {
    return msg.visit! (m => bounds.containsOrIsNotPositional (m));
}
unittest {
    AisMsg1n2n3 mIn; mIn.lat = 10; mIn.lon = 20;
    AisMsg1n2n3 mOut; mOut.lat = 191; mOut.lon = 20;
    AisMsg5     mNoPos;
    auto bounds = GeoBounds.withWorld();
    
    assert (  bounds.containsOrIsNotPositional (mIn));
    assert (! bounds.containsOrIsNotPositional (mOut));
    assert (  bounds.containsOrIsNotPositional (mNoPos));
}


//  --------------------------------------------------------------------------
//  GeoHeatmap extension
//    Helper for executeDecodeProcess()

private void markLatLon_ifPositional(T) (GeoHeatmap gh, in ref T msg) if(isAisMsg!T) {
    static if (isPositional!T)
        gh.markLatLon (msg.lat, msg.lon);
}
private void markLatLon_ifPositional (GeoHeatmap gh, in ref AnyAisMsg msg) {
    msg.visit!(m => gh.markLatLon_ifPositional (m));
}


//  --------------------------------------------------------------------------
//  Interface wrapper for DecodeProcessDef generating proper file paths to write to

private struct OutputPaths {
    private string _root;  // specified status output path minus any .txt
    import std.string;
    this (ref DecodeProcessDef pd) {
        _root = pd.outputRootFile.chomp(".txt");
        enforce (_root != "");
        messages = Messages (_root); }

    string runStats () {return _root ~ ".txt";}
    string geoMap ()   {return _root ~ "_GEOMAP.png";}
    string mmsis ()    {return _root ~ "_MMSIS.csv";}

    // Namespace for message file output paths
    // Note that we explicitly don't extend the stem, since the FileWriter's
    // add a suffix and a filetype
    private static struct Messages {
        private string* _root;
        this (ref string root) {_root = &root;}

        // All-in-one file outputs
        string aioStem () {return *_root;}

        // Simple-ship-type-split file outputs
        string bySstStem () {return *_root;}

        // Vessel-length-split file outputs
        string byShipLenStem () {return *_root;}

        // The per-day writer imposes its own (somewhat complex) suffix
        string byTsDayStem () {return *_root;}
    }
    Messages messages;
}


//  --------------------------------------------------------------------------
//  The process itself: top level runner
//    TODO simplify by moving to be a processing chain for AnyAisMsg ranges.
//
//    This function is currently difficult to read the first time, but not
//    too awful when you understand the structure. We're going to move to
//    a range-based solution asap to simplify it.
//    
//    The core work happens in stages 0,1,2,3 in the middle (you read them
//    from the bottom); messages get read and decoded, then passed to a
//    succession of higher and higher level handling functions which finally
//    write out the messages through the selected FileWriter's.
//
//    We set up the services used in executeDecodeProcess() at the top, before
//    any of these stages are reached, and write out the non-message summary
//    files at the botton once they're finished.

// Callback to know process progress
alias NotifyCB = void delegate (DecodeProcessCurRunningStats);

// Defaults to nop notify
DecProcFinStats executeDecodeProcess (DecodeProcessDef procDef) {
    return executeDecodeProcess (procDef, (crs){});
}

DecProcFinStats executeDecodeProcess (DecodeProcessDef procDef,
                                      NotifyCB notifyCB) {
    // -- Set up state to handle input lines
    
    // Used by all process variants
    auto outPaths     = OutputPaths (procDef);
    auto mmsiFilters  = MmsiFilterSet (procDef);
    auto statsBuilder = DecProcFinStats_Builder (procDef);
    //auto geoHeatmap   = new MsgGeoHeatmap (procDef);
    auto geoHeatmap   = new GeoHeatmap ();
    auto mmsiStats    = MmsiStatsBucket ();
    auto backlog      = MmsiBacklog ();
    auto grouper      = AisGrouper_BareNmea();
    auto nmea         = AisNmeaParser.make();
    ulong bytesProcessed;               // how many bytes have we read?
    ulong bytesProcessed_lastNotified;  // what did we last call notifyCB with?
    // Choose the variant-specific message file writer
    Unique!MsgFileWriter msgWriter = delegate MsgFileWriter (){
        final switch (procDef.msgOutSegment) with (MessageOutputSegmentation) {
            case AllInOne:
                return new SimpleMsgFileWriter
                    (outPaths.messages.aioStem(), procDef.messageOutputFormat);

            case VesselCategories:
                return new MsgFileWriter_SplittingSimpleShiptypes
                    (outPaths.messages.bySstStem(), procDef.messageOutputFormat);

            case ShipLenCat:
                return new MsgFileWriter_SplitShipLenCat
                    (outPaths.messages.byShipLenStem(), procDef.messageOutputFormat);

            case TimestampDay:
                return new MsgFileWriter_SplitTimestampDay
                    (outPaths.messages.byTsDayStem(), procDef.messageOutputFormat);
        } }();

    // -- Stage 3 (last): handling parsed messages

    // We've parsed an ais message, so write it or stash it
    void handleMessage(T) (T msg, Nullable!int possTS) if(isAisMsg!T) {
        statsBuilder.notifyParsedMsg ();
        bool statsChanged = mmsiStats.updateMissing (msg);
        auto stats = mmsiStats [msg.mmsi];
        
        // 1. POSS BACKLOG FLUSH: if we now have new stats for this mmsi that
        //    let us flush its backlog, do so. Otherise pass.
        if (   statsChanged
            && backlog.contains (msg.mmsi)
            && msgWriter.canWriteWithStats (stats)
            && mmsiFilters.canJudge (stats))
        {
            if (mmsiFilters.shouldWrite (stats)) {
                AnyAisMsgPossTS[] blGroup = backlog.popMmsi (msg.mmsi);
                foreach (mTS; blGroup) {
                    if (procDef.geoBounds.containsOrIsNotPositional (mTS.msg)) {
                        geoHeatmap.markLatLon_ifPositional (mTS.msg);
                        statsBuilder.notifyParsedMsgWritten ();
                        msgWriter.writeAnyAisMsg (mTS.msg, mTS.possTS, stats);
                    }
                }
            } else {
                // Discard mmsi's backlog msgs if filtered out
            }
        }

        // 2. WRITE MESSAGE, or push to backlog if filters/writer needs more info
        //    to decide whether it's worth writing or where to write it
        if (   msgWriter.canWriteWithStats (stats)
            && mmsiFilters.canJudge (stats))
        {
            // We have enough data to make the call...
            if (   mmsiFilters.shouldWrite (stats)
                && procDef.geoBounds.containsOrIsNotPositional (msg))
            {
                geoHeatmap.markLatLon_ifPositional (msg);
                msgWriter.writeMsg (msg, possTS, stats);
                statsBuilder.notifyParsedMsgWritten ();
            } else {
                // Discard as call was 'no'
            }
        } else {
            // We don't have enough data yet to make the call
            backlog.push (msg, possTS);
        }
    }
    // Called while emptying the backlog - we're more brutal here
    void handleAnyAisMessage_duringFinalBacklogFlush (in ref AnyAisMsg msg,
                                                      Nullable!int possTS) {
        auto stats = mmsiStats [msg.mmsi];
        if (// We require that the filters can make a judgement on the stats
               mmsiFilters.canJudge (stats)
            && mmsiFilters.shouldWrite (stats)
            && procDef.geoBounds.containsOrIsNotPositional (msg))
        {
            geoHeatmap.markLatLon_ifPositional (msg);
            statsBuilder.notifyParsedMsgWritten ();
            if (msgWriter.canWriteWithStats (stats))
                msgWriter.writeAnyAisMsg (msg, possTS, stats);
            else
                msgWriter.writeAnyAisMsg_noStats (msg, possTS);
        } else {
            // Discard if filtered out
        }
    }

    // -- Stage 2: parsing NMEA messages' data into AIS messages
    
    // Finished group / singlepart; we've extracted message data
    void handleCompleteNmeaData (int msgType, in string payload, size_t fillbits,
                                 Nullable!int possTS) {
        if (msgType == 1 || msgType == 2 || msgType == 3) {
            auto msg = AisMsg1n2n3 (payload, fillbits);
            handleMessage (msg, possTS);
        } else
        if (msgType == 5) {
            auto msg = AisMsg5 (payload, fillbits);
            handleMessage (msg, possTS);
        } else
        if (msgType == 18) {
            auto msg = AisMsg18 (payload, fillbits);
            handleMessage (msg, possTS);
        } else
        if (msgType == 19) {
            auto msg = AisMsg19 (payload, fillbits);
            handleMessage (msg, possTS);
        } else
        if (msgType == 24) {
            auto msg = AisMsg24 (payload, fillbits);
            handleMessage (msg, possTS);
        } else
        if (msgType == 27) {
            auto msg = AisMsg27 (payload, fillbits);
            handleMessage (msg, possTS);
        }
        else {
            // pass
        }
    }

    // -- Stage 1: get to-parse-as-ais data out of nmea lines / line groups
    
    // Called on each NMEA singlepart by handleLineNmea()
    void handleCompleteNmea (AisNmeaParser nmea) {
        Nullable!int possTS;
        if (nmea.has_tagblockval("c"))
            possTS = to!int(nmea.tagblockval("c"));
        
        handleCompleteNmeaData (nmea.aismsgtype, nmea.payload.idup,
                                nmea.fillbits, possTS);
    }
    // Called on each complete NMEA group by handleLineNmea()
    void handleCompleteNmea_gr (AisNmeaParser[] group) {
        string payload;
        foreach (nm; group)
            payload ~= nm.payload;
        auto fillbits = group[$-1].fillbits;
        auto msgType = group[0].aismsgtype;
        
        Nullable!int possTS;
        if (group[0].has_tagblockval("c"))
            possTS = to!int(group[0].tagblockval("c"));

        handleCompleteNmeaData (msgType, payload, fillbits, possTS);
    }
    // First step; run on each parsed NMEA line
    void handleLineNmea (AisNmeaParser nmea) {
        if (nmea.isSinglepart) {
            handleCompleteNmea (nmea);
        } else {
            assert (nmea.isMultipart);
            bool groupIsDone = grouper.pushMsg (nmea);
            if (groupIsDone) {
                auto group = grouper.popGroup (nmea);
                handleCompleteNmea_gr (group);
            }
        }
    }

    // -- Stage 0: the driver
    
    foreach (fileName; procDef.inputFiles.dup.sort()) {
        foreach (line; File(fileName).byLine) {
            try {
                statsBuilder.notifyInputLine (line);
                bytesProcessed += line.length + 1;  // TODO runtime check if \r\n and +2

                if (bytesProcessed - bytesProcessed_lastNotified > 40_000) {
                    notifyCB (DecodeProcessCurRunningStats (bytesProcessed,
                                                            procDef.totalBytesInInput));
                    bytesProcessed_lastNotified = bytesProcessed;
                }

                bool nmeaParsedOK = nmea.tryParse (line);
                // Ignore bad nmea lines
                if (! nmeaParsedOK)
                    continue;

                handleLineNmea (nmea);
            } catch (Exception e) {
                writeln ("#### EXCEPTION THROWN: ", e, " DURING NMEA LINE: ", line);
            }
        }
    }

    // -- Finish up and return

    foreach (mm; backlog.mmsis()) {
        AnyAisMsgPossTS[] group = backlog.popMmsi (mm);
        foreach (aamts; group)
            handleAnyAisMessage_duringFinalBacklogFlush (aamts.msg, aamts.possTS);
    }

    // Write non-message output files and return stats
    auto finStats = statsBuilder.build ();
    mmsiStats.writeCsvFile (outPaths.mmsis());
    File(outPaths.runStats(), "w").write (finStats.textSummary());
    geoHeatmap.writePng (outPaths.geoMap());
    return finStats;
}
