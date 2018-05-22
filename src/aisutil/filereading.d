//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.filereading;

import std.range, std.algorithm, std.stdio, std.typecons, std.conv;
import aisutil.ais, aisutil.daisnmea, aisutil.aisnmeagrouping,
       aisutil.dlibaiswrap;


//  ==========================================================================
//  == Classes to read (decoded) AIS data out of files on disk, either:
//  ==   - AIS-holding NMEA
//  ==   - Soon: UK Maritime and Coastguard Authority files
//  ==========================================================================


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

