//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.filewriting;
import aisutil.mmsistats, aisutil.csv, aisutil.json, aisutil.geo, aisutil.dlibaiswrap,
       aisutil.simpleshiptypes, aisutil.shiplengths;
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


//  --------------------------------------------------------------------------
//  Clients pass in a lot of possibly-present timestamps (and often deal with
//  them themselves)

alias PossTimestamp = Nullable!int;


//  --------------------------------------------------------------------------
//  Trivial json making

private string msgJsonStr(T) (in ref T msg, PossTimestamp possTS) {
    import std.json;
    auto jsval = toJsonVal (msg, possTS);
    return jsval.toJSON();
}


//  --------------------------------------------------------------------------
//  Interface followed by ALL file-writing classes

interface MsgFileWriter {
    // Can a write a message with writeMsg() given these mmsi stats?
    bool canWriteWithStats (in ref MmsiStats mmstats);

    // Write to file - normal control path
    void writeMsg (in ref AisMsg1n2n3 msg, PossTimestamp possTS, in ref MmsiStats mmstats);
    void writeMsg (in ref AisMsg5     msg, PossTimestamp possTS, in ref MmsiStats mmstats);
    void writeMsg (in ref AisMsg18    msg, PossTimestamp possTS, in ref MmsiStats mmstats);
    void writeMsg (in ref AisMsg19    msg, PossTimestamp possTS, in ref MmsiStats mmstats);
    void writeMsg (in ref AisMsg24    msg, PossTimestamp possTS, in ref MmsiStats mmstats);
    void writeMsg (in ref AisMsg27    msg, PossTimestamp possTS, in ref MmsiStats mmstats);

    // When we really don't have useful mmsi stats, write the message somehow
    void writeMsg_noStats (in ref AisMsg1n2n3 msg, PossTimestamp possTS);
    void writeMsg_noStats (in ref AisMsg5     msg, PossTimestamp possTS);
    void writeMsg_noStats (in ref AisMsg18    msg, PossTimestamp possTS);
    void writeMsg_noStats (in ref AisMsg19    msg, PossTimestamp possTS);
    void writeMsg_noStats (in ref AisMsg24    msg, PossTimestamp possTS);
    void writeMsg_noStats (in ref AisMsg27    msg, PossTimestamp possTS);

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

    mixin template WriteMsg(T) {
        void writeMsg_noStats (in ref T msg, PossTimestamp possTS) {
            final switch (_format) {
                case MessageOutputFormat.CSV:
                    _file.writeln (toCsvRow (msg, possTS));
                    break;
                case MessageOutputFormat.NDJSON:
                    auto jsval = aisutil.json.toJsonVal (msg, possTS);
                    import std.json;
                    _file.writeln (jsval.toJSON());
                    break;
            }
        }
        void writeMsg (in ref T msg, PossTimestamp possTS, in ref MmsiStats stats) {
            assert (canWriteWithStats (stats));
            writeMsg_noStats (msg, possTS); }
    }
    mixin WriteMsg!AisMsg1n2n3;
    mixin WriteMsg!AisMsg5;
    mixin WriteMsg!AisMsg18;
    mixin WriteMsg!AisMsg19;
    mixin WriteMsg!AisMsg24;
    mixin WriteMsg!AisMsg27;

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

    private void doWriteMsg(T) (File file, in ref T msg, PossTimestamp possTS) {
        final switch (_format) {
            case MessageOutputFormat.CSV:
                file.writeln (toCsvRow (msg, possTS));
                break;
            case MessageOutputFormat.NDJSON:
                auto jsval = aisutil.json.toJsonVal (msg, possTS);
                import std.json;
                file.writeln (jsval.toJSON());
                break;
        }
    }
    mixin template WriteMsg(T) {
        void writeMsg (in ref T msg, PossTimestamp possTS, in ref MmsiStats mmstats) {
            assert (canWriteWithStats (mmstats));
            auto sst = simplifyShiptype (mmstats.shiptype);
            auto file = _files [sst];
            doWriteMsg (file, msg, possTS);
        }
        void writeMsg_noStats (in ref T msg, PossTimestamp possTS) {
            auto file = _files [SimpleShiptype.NotBroadcast];
            doWriteMsg (file, msg, possTS);
        }
    }
    mixin WriteMsg!AisMsg1n2n3;
    mixin WriteMsg!AisMsg5;
    mixin WriteMsg!AisMsg18;
    mixin WriteMsg!AisMsg19;
    mixin WriteMsg!AisMsg24;
    mixin WriteMsg!AisMsg27;
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

    private void writeMsg_inFile(T) (File file, in ref T msg, PossTimestamp possTS) {
        final switch (_format) {
            case MessageOutputFormat.CSV:
                file.writeln (toCsvRow (msg, possTS));
                break;
            case MessageOutputFormat.NDJSON:
                file.writeln (msgJsonStr (msg, possTS));
                break;
        }
    }
    mixin template Writers(T) {
        void writeMsg (in ref T msg, PossTimestamp possTS, in ref MmsiStats stats) {
            assert (canWriteWithStats (stats));
            auto lenCat = stats.shiplen.shipLenCatForLen();
            auto file = _files [lenCat];
            writeMsg_inFile (file, msg, possTS);
        }
        void writeMsg_noStats (in ref T msg, PossTimestamp possTS) {
            writeMsg_inFile (_files[ShipLenCat.NotBroadcast], msg, possTS);
        }
    }
    mixin Writers!AisMsg1n2n3;
    mixin Writers!AisMsg5;
    mixin Writers!AisMsg18;
    mixin Writers!AisMsg19;
    mixin Writers!AisMsg24;
    mixin Writers!AisMsg27;
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

    private Nullable!DayID[] _openedFiles;  // we clear files and write a poss header on first open

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

    mixin template Writers(T) {
        void writeMsg (in ref T msg, PossTimestamp possTS, in ref MmsiStats stats) {
            assert (canWriteWithStats (stats));
            writeMsg_noStats (msg, possTS);
        }
        void writeMsg_noStats (in ref T msg, PossTimestamp possTS) {
            if (possTS.isNull)
                openFileWithDay (Nullable!DayID.init);
            else
                openFileWithDay (Nullable!DayID (DayID.forTimestamp (possTS)));

            writeMsg_intoCurFile (msg, possTS);
        }
    }
    mixin Writers!AisMsg1n2n3;
    mixin Writers!AisMsg5;
    mixin Writers!AisMsg18;
    mixin Writers!AisMsg19;
    mixin Writers!AisMsg24;
    mixin Writers!AisMsg27;
    
    private void writeMsg_intoCurFile(T) (in ref T msg, PossTimestamp possTS) {
        final switch (_format) with (MessageOutputFormat) {
            case CSV:
                _curFile.writeln (toCsvRow (msg, possTS));
                break;
            case NDJSON:
                _curFile.writeln (msgJsonStr (msg, possTS));
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
