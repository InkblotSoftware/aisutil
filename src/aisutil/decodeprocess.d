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
       aisutil.aisnmeagrouping, aisutil.filereading, aisutil.geotracks,
       aisutil.transits;


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
//
//    Since we can often only write messages when the static data store for
//    their MMSI has sufficient data to judge where to put the message and
//    whether we want it, we use a 'backlog' to store messages we can't yet
//    process, and check this each time we update the static data for an MMSI.
//  
//    TODO consider simplifying by further rangeifying.
//    (There's a tradeoff here with over abstraction, it's not completely
//    clear where the line is.)

// Callback to know process progress
alias NotifyCB = void delegate (DecodeProcessCurRunningStats);

// Defaults to nop notify
DecProcFinStats executeDecodeProcess (DecodeProcessDef procDef) {
    return executeDecodeProcess (procDef, (crs){});
}

DecProcFinStats executeDecodeProcess (DecodeProcessDef procDef,
                                      NotifyCB notifyCB) {
    // --- Set up state to handle input lines

    // General utils
    auto outPaths     = OutputPaths (procDef);
    auto mmsiFilters  = MmsiFilterSet (procDef);
    auto geoHeatmap   = new GeoHeatmap ();
    auto mmsiStats    = MmsiStatsBucket ();
    auto backlog      = MmsiBacklog ();
    auto geoTracker   = GeoTrackFinder ();
    auto transFinder  = TransitFinder ();
    immutable totalBytesInInput = procDef.totalBytesInInput();
    
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

    // AIS message file readers, and the messages they contain
    AisFileReader[] readers;
    final switch (procDef.aisFileFormat) {
        case AisFileFormat.NMEA:
            readers = procDef.inputFiles
                          .map!(p => cast(AisFileReader)
                                     (new AisNmeaFileReader(p)))
                          .array;
            break;
            
        case AisFileFormat.MCA:
            readers = procDef.inputFiles
                          .map!(p => cast(AisFileReader)
                                     (new McaAisFileReader(p)))
                          .array;
            break;
    }
    static assert (is( ElementType!(typeof(readers[0])) ==
                       AnyAisMsgPossTS ));
    auto allInputMsgs = joiner (readers);
    static assert (is( typeof(allInputMsgs.front) == AnyAisMsgPossTS ));

    // Collects run stats, to save at end
    auto statsBuilder = DecProcFinStats_Builder (procDef, readers);

    
    // --- Try to handle all input messages, potentially leaving a backlog

    int numMsgsSinceLastNotifyCB;  // we notify caller every 1,000 messages

    // All msg->file writing goes through these
    auto emitMessage_h = delegate void (AnyAisMsgPossTS msg,
                                      Nullable!MmsiStats stats) {
        SubtrackData stData;
        if (! msg.possTS.isNull()) {
            if (msg.msg.isPositional)
                stData.geoTrackID = geoTracker.put (msg.msg, msg.possTS);
            if (msg.msg.hasSpeed) {
                auto res = transFinder.put (msg.msg, msg.possTS);
                if (res.isInTransit)
                    stData.transitID = res.transitID;
            }
        }
        
        geoHeatmap.markLatLon_ifPositional (msg.msg);
        statsBuilder.notifyParsedMsgWritten ();
        
        if (stats.isNull)
            msgWriter.writeMsg_noStats (msg.msg, msg.possTS, stData);
        else
            msgWriter.writeMsg (msg.msg, msg.possTS, stData, stats);
    };
    auto emitMessage_noStats = delegate void (AnyAisMsgPossTS msg) {
        emitMessage_h (msg, Nullable!MmsiStats.init);
    };
    auto emitMessage_withStats = delegate void (AnyAisMsgPossTS msg,
                                                MmsiStats stats) {
        emitMessage_h (msg, Nullable!MmsiStats(stats));
    };

    // Run through all (decoded) messages in the input files
    foreach (msg; allInputMsgs) {
        // Periodic update notification to caller
        if (numMsgsSinceLastNotifyCB > 1_000) {
            notifyCB (DecodeProcessCurRunningStats (statsBuilder.bytesRead,
                                                    totalBytesInInput));
            numMsgsSinceLastNotifyCB = 0;
        }
        ++numMsgsSinceLastNotifyCB;

        // Update MMSI static data cache, and get latest
        bool statsChanged = mmsiStats.updateMissing (msg.msg);
        auto stats = mmsiStats [msg.mmsi];

        // 1. This message may have given us new static data for its MMSI.
        //    If so, can we now flush any backlog messages for that MMSI?
        if (   statsChanged
            && backlog.contains (msg.mmsi)
            && msgWriter.canWriteWithStats (stats)
            && mmsiFilters.canJudge (stats))
        {
            // Yes
            if (mmsiFilters.shouldWrite (stats)) {
                // Filters judge we want the MMSI's msgs, so write...
                AnyAisMsgPossTS[] blGroup = backlog.popMmsi (msg.mmsi);
                foreach (mTS; blGroup) {
                    if (procDef.geoBounds.containsOrIsNotPositional (mTS.msg)) {
                        // But only those msgs in geo bounds
                        emitMessage_withStats (mTS, stats);
                    }
                }
            } else {
                // Filters judge we don't want the MMSI's msgs, so discard
                backlog.popMmsi (msg.mmsi);
            }
        }

        // 2. Handle the current (this loop) message.
        //    If we can make a decision on whether to write this MMSI's msgs now,
        //    do so, or otherwise push it to the backlog
        if (   msgWriter.canWriteWithStats (stats)
            && mmsiFilters.canJudge (stats))
        {
            // Yes, can make decision now
            if (   mmsiFilters.shouldWrite (stats)
                && procDef.geoBounds.containsOrIsNotPositional (msg.msg))
            {
                emitMessage_withStats (msg, stats);
            } else {
                // Unwanted, discard
            }
        } else {
            // No, we need more data for this MMSI, so push to backlog
            backlog.push (msg.msg, msg.possTS);
        }
    } // foreach (msg; allInputMsgs)

    
    // --- All input msgs now read, so flush the backlog
    
    foreach (mmsi; backlog.mmsis()) {
        AnyAisMsgPossTS[] messages = backlog.popMmsi (mmsi);
        auto stats = mmsiStats [mmsi];
        
        // We require that the filters can make a judgement on each MMSI's stats
        // before we force-write messages from it, but not the file writer
        if (   mmsiFilters.canJudge (stats)
            && mmsiFilters.shouldWrite (stats))
        {
            foreach (msg; messages) {
                if (procDef.geoBounds.containsOrIsNotPositional(msg.msg)) {
                    if (msgWriter.canWriteWithStats (stats))
                        emitMessage_withStats (msg, stats);
                    else
                        emitMessage_noStats (msg);
                }
            }
        } else {
            // Discard, as not judgeable or not wanted
        }
    }

    
    // --- Finally write non-message output files and return stats
    
    auto finStats = statsBuilder.build ();
    mmsiStats.writeCsvFile (outPaths.mmsis());
    File(outPaths.runStats(), "w").write (finStats.textSummary());
    geoHeatmap.writePng (outPaths.geoMap());
    return finStats;
}
