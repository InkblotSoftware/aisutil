//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.filereading;

import std.range, std.algorithm, std.stdio, std.typecons, std.conv, std.traits;
import aisutil.ais, aisutil.daisnmea, aisutil.aisnmeagrouping,
       aisutil.dlibaiswrap, aisutil.mcadata;


//  ==========================================================================
//  == Classes to read (decoded) AIS data out of files on disk, either:
//  ==   - AIS-holding NMEA
//  ==   - UK Maritime and Coastguard Authority files
//  ==========================================================================


//  --------------------------------------------------------------------------
//  What file types can we read?

enum AisFileFormat {
    NMEA,  // AIS-holding NMEA data
    MCA,   // UK MCA format data (see mcadata.d for a spec)
}


//  --------------------------------------------------------------------------
//  Main file-exposing interface - we turn files into ranges of AnyAisMsgPossTSs

interface AisFileReader {
    AnyAisMsgPossTS front ();
    bool empty ();
    void popFront ();
    long bytesRead () const;    // how many file bytes so far covered?
    long linesRead () const;    // how many file input lines so far covered?
    long aisMsgsRead () const;  // how many ais msgs so far successfully parsed?
}

static assert (isInputRange!AisFileReader);


//  --------------------------------------------------------------------------
//  Helper view over AIS NMEA file, exposing as a range of parsed AisNmea objs

private struct AisNmeaLinesFile {
    private bool _justStarted = true;  // No lines yet read
    private bool _parsedOK = false;  // does the parser hold a valid parsed line?
    private AisNmeaParser _parser;  // most recently parsed line
    private File _file;
    private long _bytesRead;
    // Raw number of input lines read, not necessarily valid ones
    private long _linesRead;

    bool empty () { return ! _parsedOK; }
    
    // Returns a copy of the parser
    AisNmeaParser front () {
        assert (!empty);
        return _parser; }

    void popFront () {
        assert (!empty || _justStarted);
        _justStarted = false;
        
        foreach (line; _file.byLine) {
            _bytesRead += (line.length + 1); // TODO +2 if windows line endings
            _linesRead += 1;
                
            _parsedOK = _parser.tryParse (line);
            if (_parsedOK)
                return;
        }
        _parsedOK = false;  // nothing left to parse
    }

    @disable this();
    this (in string filepath) {
        _file = File (filepath, "r");
        _parser = AisNmeaParser .make();
        popFront ();
    }

    long bytesRead () const { return _bytesRead; }
    long linesRead () const { return _linesRead; }
}
    

//  --------------------------------------------------------------------------
//  AIS NMEA file reader
//  
//    Groups multipart messages together as necessary.
//    
//    Silently discards lines that don't parse properly, either at an NMEA
//    level or an AIS wire format level.

class AisNmeaFileReader : AisFileReader {
    private bool _justStarted = true;  // no data yet read
    
    private long _aisMsgsRead;
    
    private AisNmeaLinesFile         _nmeaLines;
    private auto                     _grouper = AisGrouper_BareNmea ();
    // Null when no more msgs to read
    private Nullable!AnyAisMsgPossTS _curMsg;


    @disable this();
    this (in string filepath) {
        _nmeaLines = AisNmeaLinesFile (filepath);
        popFront ();
    }

    override bool empty () const { return _curMsg.isNull; }

    override AnyAisMsgPossTS front () const {
        assert (!empty);
        return _curMsg.get; }

    override long bytesRead () const { return _nmeaLines.bytesRead; }
    override long linesRead () const { return _nmeaLines.linesRead; }
    override long aisMsgsRead () const { return _aisMsgsRead; }

    // Loop until we successfully parse a message, or run out of lines
    override void popFront () {
        assert (!empty || _justStarted);
        _justStarted = false;

        while (! _nmeaLines.empty) {
            auto nmea = _nmeaLines.front;
            scope (exit) _nmeaLines.popFront ();

            try {
                if (nmea.isSinglepart) {
                    popFront_singlepart ();
                    ++_aisMsgsRead;
                    return;
                } else {
                    auto stop = popFront_multipart ();
                    if (stop) {
                        ++_aisMsgsRead;
                        return;
                    }
                }

            // TODO perhansp don't use an exception for this, it's not
            // really surprising we get message types we don't decode
            } catch (UnparseableMessageTypeException e) {
                // nop - silently discard
                
            } catch (Exception e) {
                stderr.writeln ("== AIS parse failed on NMEA line: ",
                                _nmeaLines.front, " - ", e);
            }
        }

        // No more messages to read
        _curMsg.nullify ();
    }
    
    // -- Helpers for popFront. NB these do the _nmeaLines.popFront()

    private void popFront_singlepart () {
        auto nmea = _nmeaLines.front;
        auto msg = parseAnyAisMsg (nmea.aismsgtype, nmea.payload,
                                   nmea.fillbits);
        Nullable!int possTS;
        if (nmea.has_tagblockval("c"))
            possTS = to!int (nmea.tagblockval("c"));
        
        _curMsg = AnyAisMsgPossTS (msg, possTS);
    }

    // Returns true iff popFront() now has a complete group and should stop
    private bool popFront_multipart () {
        auto nmea = _nmeaLines.front;
        auto groupDone = _grouper.pushMsg (nmea);
        
        if (groupDone) {
            auto group = _grouper.popGroup (nmea);
                        
            string payload;
            foreach (nm; group)
                payload ~= nm.payload;
            auto fillbits = group[$-1].fillbits;
            auto msgType = group[0].aismsgtype;
            auto msg = parseAnyAisMsg (msgType, payload, fillbits);

            Nullable!int possTS;
            if (group[0].has_tagblockval("c"))
                possTS = to!int (group[0].tagblockval("c"));

            _curMsg = AnyAisMsgPossTS (msg, possTS);
            return true;
                
        } else {
            return false;
        }
    }
}


//  --------------------------------------------------------------------------
//  Tests for AIS NMEA readers

// We dump this to a temp file during unit tests
private immutable aisNmeaFileData = r"
xasdf
!AIVDM,1,1,,B,B5MiOp0006g4up6:EV403wr5oP06,0*38

lwfe
!AIVDM,1,1,,B,YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY,0*38
!AIVDM,1,1,,B,YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY,0*38

!AIVDM,1,1,,B,HE2K5MA`58hTpL0000000000000,2*37

!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::4A80?4i@E53,0*3E
!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C
ppppppppppp
!AIVDM,2,2,3,B,1@0000000000000,2*55
";

unittest {
    import std.file, std.path;
    auto dataFile = tempDir().buildPath ("AISUTIL_UNITTEST_aisNmeaFileData.nmea");
    //assert (! exists(dataFile));
    dataFile.write (aisNmeaFileData);
    scope(exit) dataFile.remove();

    // -- Test basic nmea reading first
    {
        auto reader = AisNmeaLinesFile (dataFile);

        assert (!reader.empty);
        assert (reader.front.payload == "B5MiOp0006g4up6:EV403wr5oP06");

        reader.popFront ();
        assert (!reader.empty);
        assert (reader.front.payload == "HE2K5MA`58hTpL0000000000000");

        reader.popFront ();
        assert (!reader.empty);
        assert (reader.front.payload == "55P5TL01VIaAL@7WKO@mBplU@<PDhh0" ~
                                        "00000001S;AJ::4A80?4i@E53");

        reader.popFront ();
        assert (!reader.empty);
        assert (reader.front.payload == "177KQJ5000G?tO`K>RA1wUbN0TKH");

        reader.popFront ();
        assert (!reader.empty);
        assert (reader.front.payload == "1@0000000000000");

        reader.popFront ();
        assert (reader.empty);

        assert (reader.bytesRead == aisNmeaFileData.length);
        assert (reader.linesRead == 14);
    }

    // -- Now test the AIS parsing wrapper
    {
        auto reader = new AisNmeaFileReader (dataFile);

        assert (!reader.empty);
        assert (reader.front.msg.get!AisMsg18.mmsi == 366764000);

        reader.popFront();
        assert (!reader.empty);
        assert (reader.front.msg.get!AisMsg24.mmsi == 338085237);

        reader.popFront();
        assert (!reader.empty);
        assert (reader.front.msg.get!AisMsg1n2n3.mmsi == 477553000);

        reader.popFront();
        assert (!reader.empty);
        assert (reader.front.msg.get!AisMsg5.mmsi == 369190000);

        reader.popFront();
        assert (reader.empty);

        assert (reader.bytesRead == aisNmeaFileData.length);
    }    
}


//  --------------------------------------------------------------------------
//  UK Maritime and Coastguard Authority AIS data file reader
//    This is a proprietary format which adds timestamps, merges multipart
//    messages together, adds a few pre-decoded fields, and, comically,
//    discards the fillbits field, which we have to guess from the message
//    type.

class McaAisFileReader : AisFileReader {
    // Null if no more messages in file to read
    private Nullable!AnyAisMsgPossTS _curMsg;
    // Are we yet to try reading any data
    private bool _justStarted = true;
    // Lines to read from input file
    private typeof(File().byLine()) _inputLines;
    
    private long _bytesRead;
    private long _linesRead;
    private long _aisMsgsRead;

    @disable this();
    this (in string filepath) {
        _inputLines =  File(filepath, "r").byLine();
        popFront ();
    }

    override long bytesRead () const { return _bytesRead; }
    override long linesRead () const { return _linesRead; }
    override long aisMsgsRead () const { return _aisMsgsRead; }

    override bool empty () const { return _curMsg.isNull; }
    
    override AnyAisMsgPossTS front () const {
        assert (!empty);
        return _curMsg.get; }

    override void popFront () {
        assert (!empty || _justStarted);
        _justStarted = false;

        // Loop until we successfully parse a message, or run out of lines
        while (! _inputLines.empty) {
            scope(exit) _inputLines.popFront ();
            auto line = _inputLines.front;
            
            _linesRead += 1;
            _bytesRead += (line.length + 1); // TODO +2 for windows line endings

            try {
                auto dats = McaDataLine (line);
                auto msg = parseAnyAisMsg (dats.payloadMsgType, dats.payload,
                                           dats.guessedFillbits);
                _curMsg = AnyAisMsgPossTS (msg, Nullable!int(dats.timestamp));
                ++_aisMsgsRead;
                return;
                
            } catch (Exception e) {
                stderr.writeln ("== MCA data parse failed, CONTINUING. ",
                                "Line was: ", line, "\n", e);
                stderr.flush;
            }
        }
        _curMsg.nullify ();  // no more data to read, so give up, we're empty
    }
}


//  --------------------------------------------------------------------------
//  Tests for MCA data reader

// We dump this to a temp file during unit tests
private immutable mcaAisFileData = "
2013-10-17 00:00:00,306033000,5,54SniJ02>6K10a<J2204l4p@622222222222221?:hD:46b`0>E3lSRCp88888888888880
oooo
2016-04-29 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000     \r
2016-04-29 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000
";

unittest {
    import std.file, std.path, std.string;
    auto dataFile = tempDir().buildPath ("AISUTIL_UNITTEST_mcaAisFileData.data");
    //assert (! exists(dataFile));
    dataFile.write (mcaAisFileData);
    scope(exit) dataFile.remove();

    auto reader = new McaAisFileReader (dataFile);

    // {u'destination': u'TORNIO              ', u'dim_d': 4L, u'name': u'AMANDA              ', u'eta_hour': 8L, u'ais_version': 0L, u'draught': 5.699999809265137, u'mmsi': 306033000L, u'repeat_indicator': 0L, u'dim_b': 20L, u'dim_c': 10L, u'dte': 0L, u'dim_a': 86L, u'eta_day': 21L, u'eta_minute': 0L, u'callsign': u'PJSF   ', u'spare': 0L, u'eta_month': 10L, u'type_and_cargo': 79L, u'fix_type': 1L, u'id': 5L, u'imo_num': 9312688L}
    assert (! reader.empty);
    assert (reader.front.msg.get!AisMsg5.shipname.fromStringz == "AMANDA");
    assert (reader.front.msg.get!AisMsg5.mmsi == 306033000);

    // {u'mmsi': 235104485L, u'repeat_indicator': 0L, u'id': 24L, u'name': u'EYECATCHER@@@@@@@@@@', u'part_num': 0L}
    reader.popFront ();
    assert (! reader.empty);
    assert (reader.front.msg.get!AisMsg24.shipname.fromStringz == "EYECATCHER");
    assert (reader.front.msg.get!AisMsg24.mmsi == 235104485);

    // Same again
    reader.popFront ();
    assert (! reader.empty);
    assert (reader.front.msg.get!AisMsg24.shipname.fromStringz == "EYECATCHER");
    assert (reader.front.msg.get!AisMsg24.mmsi == 235104485);
    
    reader.popFront ();
    assert (reader.empty);

    assert (reader.linesRead == 5);
    assert (reader.bytesRead == mcaAisFileData.length);
    assert (reader.aisMsgsRead == 3);
}
