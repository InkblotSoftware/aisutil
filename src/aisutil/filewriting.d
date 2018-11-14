//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.filewriting;
import aisutil.mmsistats, aisutil.csv, aisutil.json, aisutil.geo,
       aisutil.dlibaiswrap, aisutil.simpleshiptypes, aisutil.shiplengths,
       aisutil.ais, aisutil.geotracks, aisutil.transits;
import std.stdio, std.range, std.algorithm, std.typecons;


//  ==========================================================================
//  == Classes writing message-holding output csv/ndjson files
//  ==
//  ==   The basic idea is that you present a message and what you know of its
//  ==   MMSI's static data, and the class tells you whether it's able to write
//  ==   the message. If it is, you can call writeMsg(), or otherwise you need
//  ==   to queue the message in a backlog.
//  ==
//  ==   At the end of a run you'll likely have no more static data messages to
//  ==   read, but some messages still stored in a backlog. Then you call
//  ==   writeMsg_noStats() to force the writer to write the message *somewhere*
//  ==   (usually in a 'not broadcast' file or similar).
//  ==
//  ==   Note that some writers ignore mmsi stats, e.g. when writing all
//  ==   messages to one file, in which case writeMsg() and writeMsg_noStats()
//  ==   do the same thing.
//  ==
//  ==   NB you MUST call close() when you're done writing, or alternatively
//  ==   use an RAII-style construct like unique-ptr that does the same thing.
//  ==========================================================================


//  --------------------------------------------------------------------------
//  What file types can we write messages as?

enum MessageOutputFormat {
    NDJSON,
    CSV
}


//  ----------------------------------------------------------------------
//  Each message may or may not be part of an MMSI geotrack and/or a transit,
//  which together make up it's 'subtrack membership'

struct SubtrackData {
    Nullable!GeoTrackID geoTrackID;
    Nullable!TransitID  transitID;
}


//  --------------------------------------------------------------------------
//  Clients pass in a lot of possibly-present timestamps and GeoTrackIDs
//  (and often deal with them themselves)

alias PossTimestamp  = Nullable!int;
alias PossGeoTrackID = Nullable!GeoTrackID;


//  --------------------------------------------------------------------------
//  Trivial json making

private string msgJsonStr (in ref AnyAisMsg msg, PossTimestamp possTS,
                           SubtrackData stData) {
    import std.json;
    auto jsval = toJsonVal (msg, possTS, stData);
    return jsval.toJSON();
}


//  --------------------------------------------------------------------------
//  Interface followed by ALL file-writing classes

interface MsgFileWriter {
    // Can a write a message with writeMsg() given these mmsi stats?
    bool canWriteWithStats (in ref MmsiStats mmstats);

    // Write to file - normal control path
    void writeMsg (in ref AnyAisMsg msg, PossTimestamp possTS,
                   SubtrackData stData, in ref MmsiStats mmstats);
    
    // When we really don't have useful mmsi stats, write the message somehow
    void writeMsg_noStats (in ref AnyAisMsg msg, PossTimestamp possTS,
                           SubtrackData stData);

    // Close all open files. MUST be called in class dtr
    void close();
}


//  --------------------------------------------------------------------------
//  Basic 'all in one file' writer
//    Ignores any provided mmsi stats.

class SimpleMsgFileWriter : MsgFileWriter {
    private File _file;
    private MessageOutputFormat _format;

    this (in string baseFilePath, MessageOutputFormat format) {
        _format = format;

        string suffix = (){ final switch (format) {
                            case MessageOutputFormat.CSV:    return ".csv";
                            case MessageOutputFormat.NDJSON: return ".ndjson";} }();
        _file = File (baseFilePath ~ suffix, "w");
        
        final switch (_format) {
            case MessageOutputFormat.CSV:
                _file.writeln (csvHeader);
                break;
            case MessageOutputFormat.NDJSON:
                // pass
                break;
        }
    }

    // We don't use the stats
    override bool canWriteWithStats (in ref MmsiStats mmstats) {return true;}

    override void writeMsg (in ref AnyAisMsg msg, PossTimestamp possTS,
                            SubtrackData stData,
                            in ref MmsiStats stats) {
        assert (canWriteWithStats (stats));
        writeMsg_noStats (msg, possTS, stData);
    }

    override void writeMsg_noStats (in ref AnyAisMsg msg, PossTimestamp possTS,
                                    SubtrackData stData) {
        final switch (_format) {
            case MessageOutputFormat.CSV:
                _file.writeln (toCsvRow (msg, possTS, stData));
                break;
            case MessageOutputFormat.NDJSON:
                auto jsval = aisutil.json.toJsonVal (msg, possTS, stData);
                import std.json;
                _file.writeln (jsval.toJSON());
                break;
        }
    }

    void close() {
        _file.close();
    }
    ~this() {close();}
}


//  --------------------------------------------------------------------------
//  Message file writer splitting messages based on known simple ship type

class MsgFileWriter_SplittingSimpleShiptypes : MsgFileWriter {
    private MessageOutputFormat _format;
    private File[SimpleShiptype] _files;  // files we write to

    void close() {
        foreach (f; _files.byValue)
            f.close();
    }
    ~this() {close();}

    this (in string baseFilePath, MessageOutputFormat format) {
        _format = format;

        string suffix = (){ final switch (format) {
                            case MessageOutputFormat.CSV:    return ".csv";
                            case MessageOutputFormat.NDJSON: return ".ndjson";} }();

        // Make a File in _files for each member of enum SimpleShiptype
        static foreach (sst; __traits(allMembers, SimpleShiptype)) {
            _files [__traits(getMember, SimpleShiptype, sst)] =
                File (baseFilePath ~ "_shiptype_" ~ sst ~ suffix, "w");
        }
        
        final switch (_format) {
            case MessageOutputFormat.CSV:
                foreach (f; _files.byValue)
                    f.writeln (csvHeader);
                break;
            case MessageOutputFormat.NDJSON:
                // pass
                break;
        }
    }

    // -- Message writing implementation

    override bool canWriteWithStats (in ref MmsiStats mmstats) {
        return mmstats.hasShiptype;
    }

    override void writeMsg (in ref AnyAisMsg msg, PossTimestamp possTS,
                            SubtrackData stData,
                            in ref MmsiStats stats) {
        assert (canWriteWithStats (stats));
        auto sst = simplifyShiptype (stats.shiptype);
        auto file = _files [sst];
        doWriteMsg (file, msg, possTS, stData);
    }

    override void writeMsg_noStats (in ref AnyAisMsg msg, PossTimestamp possTS,
                                    SubtrackData stData) {
        auto file = _files [SimpleShiptype.NotBroadcast];
        doWriteMsg (file, msg, possTS, stData);
    }

    private void doWriteMsg (File file, in ref AnyAisMsg msg,
                             PossTimestamp possTS, SubtrackData stData) {
        final switch (_format) {
            case MessageOutputFormat.CSV:
                file.writeln (toCsvRow (msg, possTS, stData));
                break;
            case MessageOutputFormat.NDJSON:
                auto jsval = aisutil.json.toJsonVal (msg, possTS, stData);
                import std.json;
                file.writeln (jsval.toJSON());
                break;
        }
    }
}


//  --------------------------------------------------------------------------
//  Message file writer segmenting messages based on vessel length category

class MsgFileWriter_SplitShipLenCat : MsgFileWriter {
    private MessageOutputFormat _format;
    private File [ShipLenCat] _files;

    void close() {_files.byValue().each!(f => f.close());}
    ~this ()     {close();}

    this (in string baseFilePath, MessageOutputFormat format) {
        _format = format;

        string suffix = (){ final switch (format) {
                            case MessageOutputFormat.CSV:    return ".csv";
                            case MessageOutputFormat.NDJSON: return ".ndjson";} }();

        // Make a File in _files for each member of enum ShipLenCat
        static foreach (catName; __traits(allMembers, ShipLenCat)) {
            _files [__traits(getMember, ShipLenCat, catName)] =
                File (baseFilePath ~ "_shiplen_" ~ catName ~ suffix, "w");
        }

        final switch (_format) {
            case MessageOutputFormat.CSV:
                _files.byValue.each! (f => f.writeln(csvHeader));
                break;
            case MessageOutputFormat.NDJSON:
                break;
        }
    }

    // -- Writing messages

    override bool canWriteWithStats (in ref MmsiStats stats) {
        return stats.hasShiplen; }

    override void writeMsg (in ref AnyAisMsg msg, PossTimestamp possTS,
                            SubtrackData stData, in ref MmsiStats stats) {
        assert (canWriteWithStats (stats));
        auto lenCat = stats.shiplen.shipLenCatForLen ();
        auto file = _files [lenCat];
        doWriteMsg (file, msg, possTS, stData);
    }

    override void writeMsg_noStats (in ref AnyAisMsg msg, PossTimestamp possTS,
                                    SubtrackData stData) {
                                    //PossGeoTrackID possGtid) {
        auto file = _files [ShipLenCat.NotBroadcast];
        doWriteMsg (file, msg, possTS, stData);
    }

    void doWriteMsg (File file, in ref AnyAisMsg msg,
                     PossTimestamp possTS, SubtrackData stData) {
        final switch (_format) {
            case MessageOutputFormat.CSV:
                file.writeln (toCsvRow (msg, possTS, stData));
                break;
            case MessageOutputFormat.NDJSON:
                file.writeln (msgJsonStr (msg, possTS, stData));
                break;
        }
    }
}


//  --------------------------------------------------------------------------
//  Message file writer segmenting output files based on broadcast day
//    TODO poss look at perf here - we may be doing too many file opens

class MsgFileWriter_SplitTimestampDay : MsgFileWriter {
    // -- Member vars
    
    private MessageOutputFormat _format;
    private string _baseFilePath;
    private string _suffix;

    // holds messages for day _dayForCurFile
    private File  _curFile;
    // where is _curFile pointed; null means 'the no-day file'
    private Nullable!DayID _dayForCurFile;

    // we clear files and write a poss header on first open
    private Nullable!DayID[] _openedFiles;  

    // -- Files on disk
    
    private struct DayID {
        int day, month, year;
        static DayID forTimestamp (int ts) {
            import std.datetime;
            auto st = SysTime (ts.unixTimeToStdTime, UTC());
            return DayID (st.day, st.month, st.year); }
    }
    private void openFileWithDay (Nullable!DayID did) {
        if (_dayForCurFile == did)
            return;
        _dayForCurFile = did;

        import std.string;
        string filePath = did.isNull
                   ? _baseFilePath ~ "_day_NoTimestamp" ~ _suffix
                   : format ("%s_day_%.2d-%.2d-%.4d%s", _baseFilePath,
                             did.day, did.month, did.year, _suffix);

        // Open the file, clearing and writing a header if it's the first time
        if (_openedFiles.canFind (did)) {
            _curFile = File (filePath, "a");
        } else {
            _openedFiles ~= did;
            _curFile = File (filePath, "w");
            final switch (_format) with (MessageOutputFormat) {
                case CSV:
                    _curFile.writeln (csvHeader);
                    break;
                case NDJSON:
                    break;
            }
        }
    }

    // -- Class funs
    
    override void close () {_curFile.close();}
    ~this ()               {close();}

    this (in string baseFilePath, MessageOutputFormat format) {
        _format = format;
        _baseFilePath = baseFilePath;

        _suffix = (){ final switch (format) {
                      case MessageOutputFormat.CSV:    return ".csv";
                      case MessageOutputFormat.NDJSON: return ".ndjson";} }();
    }

    // -- Writing messages

    override bool canWriteWithStats (in ref MmsiStats stats) const {return true;}

    override void writeMsg (in ref AnyAisMsg msg, PossTimestamp possTS,
                            SubtrackData stData, in ref MmsiStats stats) {
        assert (canWriteWithStats (stats));
        writeMsg_noStats (msg, possTS, stData);
    }

    override void writeMsg_noStats (in ref AnyAisMsg msg, PossTimestamp possTS,
                                    SubtrackData stData) {
        if (possTS.isNull)
            openFileWithDay (Nullable!DayID.init);
        else
            openFileWithDay (Nullable!DayID (DayID.forTimestamp (possTS)));

        writeMsg_intoCurFile (msg, possTS, stData);
    }

    private void writeMsg_intoCurFile (in ref AnyAisMsg msg,
                                       PossTimestamp possTS,
                                       SubtrackData stData) {
        final switch (_format) with (MessageOutputFormat) {
            case CSV:
                _curFile.writeln (toCsvRow (msg, possTS, stData));
                break;
            case NDJSON:
                _curFile.writeln (msgJsonStr (msg, possTS, stData));
                break;
        }
    }
}

unittest {
    alias DID = MsgFileWriter_SplitTimestampDay.DayID;
    DID d1 = { day: 11, month: 22, year: 33 };
    DID d2 = { day: 11, month: 22, year: 33 };
    DID d3 = { day: 01, month: 22, year: 33 };
    assert (d1 == d2);
    assert (d1 != d3);
 }
