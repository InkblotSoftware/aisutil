module aisutil.mcadata;

//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

import std.range, std.algorithm, std.conv, std.exception, std.typecons,
       std.traits, std.string;
import aisutil.ais;


//  ==========================================================================
//  == Types and functions for parsing UK Maritime and Coastguard Authority
//  == AIS data (they have an internal format which is somewhat like AIS-
//  == holding NMEA, but different as described below).
//  ==
//  ==   We only handle the MCA data layer here, not decoding the AIS payload;
//  ==   see ais.d for that.
//  ==========================================================================


//  --------------------------------------------------------------------------
//  -- Format spec, as well as I can infer from working with it:
//  --------------------------------------------------------------------------
//
//  E.g. a typical line:
//    -> 2013-10-17 00:00:00,306033000,5,54SniJ02>6K10a<J2204l4p@622222222222221?:hD:46b`0>E3lSRCp88888888888880
//  Or another in a slightly different format:
//    -> 2016-04-29 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000
//
//  It's a CSV-style format, as ever, and one that doesn't quote strings
//  containing spaces.
//  You get four fields in the first format, and three in the latter.
//  
//  Note that we need to handle arbitrary numbers of trailing spaces on the
//  lines, as well as sometimes-present windows line endings.
//
//  Timestamp comes first, stored in "YYYY-mm-dd HH:MM:SS.XXX" format, where
//  the '.XXX. fractional part may or may not exist.
//  I'm assuming this is in UTC, but it may (rather unfortunately) be stored in
//  UK local time, which would impose a one-hour daylight saving shift in summer.
//  I'm currently seeking confirmation here, or alternatively if you have a
//  dataset that spans the beginning or the end of the daylight saving period
//  and tell me whether there's an overlap or a gap, please let me know in an
//  issue.
//
//  Second we have the MMSI of the message, though I think this is just taken
//  verbatim from the starting bits without decoding the whole message, as it
//  still appears for some seemingly invalid messages. (Note that since this can
//  be inferred from the payload, it's technically redundant.)
//
//  Third, if we're a four-field message we get an integer stating the AIS
//  message type of the message. (Note that this can again be inferred from
//  the payload, so is technically redundant.)
//
//  Instead, if we're in a three-field line, the third field carries the AIS
//  message payload, with multipart messages pre-concatenated, so you always
//  get the whole thing. Comically, however, the fillbits seem to have been
//  discarded, and must be guessed. See later in this file for the logic we use;
//  it works, since the MCA includes only a very restricted set of message types,
//  but I don't like having to do this.
//
//  Finally in a four-field line, the fourth field is equivalent to the third
//  field of a three-field line, i.e. concatenated payload.
//
//  Note that some MCA data files start with a BOM, so you'll have to be
//  prepared to handle this.
//
//  TODO check the timestamp is UTC, not UK local time.


//  --------------------------------------------------------------------------
//  CSV line parsing

// -- Core 'parsed line' type

struct McaDataLine {
    int timestamp;   // unix epoch time
    int mmsi;        // as given in line, nb check against payload when you parse
    string payload;  // as given in line
    Nullable!int msgType;  // as given in line, pre-checked against payload

    @disable this();
    this(T) (in T line) if(isSomeString!T) {
        immutable string bom = [0xEF, 0xBB, 0xBF];
        auto stripLine = line .stripRight(" \r") .stripLeft(bom);
        auto fields = stripLine.split(",");

        if (fields.length == 3) {
            timestamp = parseMcaTimestamp (fields[0]);
            mmsi = to!int (fields[1]);
            payload = fields[2].dup;
            
        } else
        if (fields.length == 4) {
            timestamp = parseMcaTimestamp (fields[0]);
            mmsi = to!int (fields[1]);
            msgType = to!int (fields[2]);
            payload = fields[3].dup;

            enforce (payloadMsgType() == msgType);
        }
        else {
            enforce (false, "Bad number of CSV fields");
        }

        enforce (payload.length >= 1, "Missing payload");
    }

    // Always succeeds (modulo data errors), whether msgType.isNull or not
    int payloadMsgType () const { return payloadAisMsgType (payload); }

    // Examine the payload to guess what the nmea fillbits value was
    int guessedFillbits () const {
        auto ty = payloadMsgType ();
        
        if (ty == 1 || ty == 2 || ty == 3) {
            return 0;
        } else
        if (ty == 5) {
            return 2;
        } else
        if (ty == 18) {
            return 0;
        } else
        if (ty == 19) {
            return 0;
        } else
        if (ty == 24) {
            if (payload.length == 28) {
                return 0;
            } else
            if (payload.length == 27) {
                return 2;
            } else {
                enforce (false, format("Bad payload length for type 24 " ~
                                       "message: %s", payload));
            }
        } else {
            enforce (false, "Unhandled message type");
        }
        assert (0);  // placate compiler
    }
}

// -- Helpers

// Line string timestamp to unix timestamp conversion
// Throws on error
private int parseMcaTimestamp(T) (in T ts) if(isSomeString!T) {
    import std.regex;
    auto reg = ctRegex !(  `^(\d{4})-(\d{2})-(\d{2})`     // date part
                         ~ ` (\d{2}):(\d{2}):(\d{2})(.\d+)?$`); // time part

    auto capts = matchFirst (ts, reg);
    enforce (! capts.empty, "Timestamp in wrong format: ---" ~ ts ~ "---");
    
    auto tsYear  = to!int (capts[1]);
    auto tsMonth = to!int (capts[2]);
    auto tsDay   = to!int (capts[3]);
    auto tsHour  = to!int (capts[4]);
    auto tsMin   = to!int (capts[5]);
    auto tsSec   = to!int (capts[6]);
    
    import std.datetime;
    // TODO check this is UTC not UK local time
    auto st = SysTime (DateTime (tsYear, tsMonth, tsDay, tsHour, tsMin, tsSec),
                        UTC());
    auto longRes = st.toUnixTime;
    enforce (longRes < int.max, "Line timestamp too large to represent");
    return cast(int) longRes;
}

private int payloadAisMsgType (in string payload) {
    enforce (payload.length >= 1);
    switch (payload[0]) {
        case '1': return 1;
        case '2': return 2;
        case '3': return 3;
        case '5': return 5;
        case 'B': return 18;
        case 'C': return 19;
        case 'H': return 24;
        default:
            enforce (false, "Unhandled AIS message type");
            assert (0);  // pacify compiler, we can't hit this
    }
}

// -- Tests for all of these
    
unittest {
    // Four field line
    {
        immutable line = "2013-10-17 00:00:00,306033000,5,54SniJ02>6K10a<J2204l4p@622222222222221?:hD:46b`0>E3lSRCp88888888888880    \r";
        auto par = McaDataLine (line);
        assert (par.timestamp == 1381968000);
        assert (par.mmsi == 306033000);
        assert (par.msgType == 5);
        assert (par.payload == "54SniJ02>6K10a<J2204l4p@622222222222221?:hD:46b`0>E3lSRCp88888888888880");
        assert (par.guessedFillbits == 2);
    }

    // Three field line
    {
        immutable line = "2016-04-29 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000    \r";
        auto par = McaDataLine (line);
        assert (par.timestamp == 1461888000);
        assert (par.mmsi == 235104485);
        assert (par.msgType.isNull);
        assert (par.payload == "H3P=`q@ETD<5@<PE80000000000");
        assert (par.guessedFillbits == 2);
    }

    // Bad lines
    {
        // Timestamps
        assertThrown (McaDataLine ("2016xxx-04-29 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000"));
        assertThrown (McaDataLine ("2016-04-99 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000"));

        // Bad msg type (should be 5 not 99)
        assertThrown (McaDataLine ("2013-10-17 00:00:00,306033000,99,54SniJ02>6K10a<J2204l4p@622222222222221?:hD:46b`0>E3lSRCp88888888888880"));
    }
}
        
