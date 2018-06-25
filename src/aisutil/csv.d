//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.csv;
import std.string, std.range, std.algorithm, std.conv, std.typecons, std.variant;
import aisutil.ext.libaiswrap, aisutil.ais, aisutil.dlibaiswrap;


// Functions to generate CSV strings, particularly for AIS messages
// ================================================================
//
// The format created is compatible with the variant Excel uses.


//  --------------------------------------------------------------------------
//  Generating CSV value strings (for individual fields)
//    NB strings are escaped and surrounded by '"' quotes

// -- Direct val->string conversions

string csvValStr (string str) {
    return "\"" ~ str.replace("\"", "\"\"") ~ "\"";
}
string csvValStr (const(char)* str) {
    return (to!string(str)).csvValStr; }

string csvValStr (int    num) { return to!string(num); }
string csvValStr (double num) { return "%.18g".format(num); }
string csvValStr (bool   val) { return to!string(val); }


// -- Possibly-null versions of the above (null gives an empty field)

string csvValStr (Nullable!double num) {
    if (num.isNull) return "";
    else            return csvValStr (num.get);
}
string csvValStr (Nullable!int num) {
    if (num.isNull) return "";
    else            return csvValStr (num.get);
}
string csvValStr (Nullable!string num) {
    if (num.isNull) return "";
    else            return csvValStr (num.get);
}


// -- Tests

unittest {
    assert (" some\"string".csvValStr == "\" some\"\"string\"");
    assert (" some\"string".ptr.csvValStr == "\" some\"\"string\"");
    assert (123.csvValStr == "123");
    // Correct value on linux x64 dmd without optimisation.
    // Patches welcome if wrong on other setups.
    assert (csvValStr (123.123) == "123.123000000000005");

    // As above, correct on linux x64 dmd w/o optimisation
    Nullable!double num = 123.123;
    assert (csvValStr (num) == "123.123000000000005");
    num.nullify();
    assert (csvValStr (num) == "");
}


//  --------------------------------------------------------------------------
//  Names of all the fields used in AIS messages, plus a tb timestamp
//    These are used to generate headers and uniform rows for AIS objects, the
//    latter by static reflection

private immutable string[] ignoredFields = ["parse_error", "turn_valid"];

private immutable string[] aisCsvCols = "tagblock_timestamp"
                                        ~
                                        (  [__traits(allMembers, C_AisMsg1n2n3)]
                                         ~ [__traits(allMembers, C_AisMsg5)]
                                         ~ [__traits(allMembers, C_AisMsg18)]
                                         ~ [__traits(allMembers, C_AisMsg19)]
                                         ~ [__traits(allMembers, C_AisMsg24)]
                                         ~ [__traits(allMembers, C_AisMsg27)])
                                            .filter !(c => !ignoredFields.canFind(c))
                                            .array.sort.uniq.array;


//  --------------------------------------------------------------------------
//  Header row for AIS message CSVs

string csvHeader() {
    return aisCsvCols.join(",");
}


//  --------------------------------------------------------------------------
//  Making CSV rows from AIS messages
//    Where a field doesn't exist in the passed AisMsg struct we write an
//    empty cell, or similarly if the relevant value is deemed null by the fixer

// -- AnyAisMsg wrapper

string toCsvRow (in AnyAisMsg msg) {
    return toCsvRow (msg, Nullable!int.init);
}
string toCsvRow (in AnyAisMsg msg, Nullable!int tagblockTimestamp) {
    return msg.visit!(
        (in ref AisMsg1n2n3 m) => toCsvRow (m, tagblockTimestamp),
        (in ref AisMsg5     m) => toCsvRow (m, tagblockTimestamp),
        (in ref AisMsg18    m) => toCsvRow (m, tagblockTimestamp),
        (in ref AisMsg19    m) => toCsvRow (m, tagblockTimestamp),
        (in ref AisMsg24    m) => toCsvRow (m, tagblockTimestamp),
        (in ref AisMsg27    m) => toCsvRow (m, tagblockTimestamp)
    );
}

// -- Distinct message type handlers

string toCsvRow(T)(in T obj) if(isAisMsg!T) {
    return toCsvRow!T(obj, Nullable!int.init);
}
string toCsvRow(T)(in T obj, Nullable!int tagblockTimestamp) if(isAisMsg!T) {
    import std.conv;
    string res;
    bool doneFirst = false;

    auto fixer = aisValueFixer (obj);

    static foreach (cn; aisCsvCols) {
        if (doneFirst) res ~= ",";
        doneFirst = true;

        // tbts is special
        static if (cn == "tagblock_timestamp") {
            if (tagblockTimestamp.isNull) {
                // pass
            } else {
                res ~= tagblockTimestamp.get.csvValStr();
            }
        } else
        static if (__traits (hasMember, obj, cn)) {
            // Every other present field is handled the same way
            
            // check for a has_xxx member, and if present only fetch if it rets true
            static if (__traits (hasMember, obj, "has_" ~ cn)) {
                if (__traits (getMember, obj, "has_" ~ cn))
                    res ~= __traits (getMember, fixer, cn).csvValStr();
            } else {
                res ~= __traits (getMember, fixer, cn).csvValStr();
            }
        } else {
            // pass (if no such member)
        }
    }
    
    return res;
}

unittest {
    import aisutil.dlibaiswrap;
    
    // Type 24A (no null fields)
    {
        auto msg = AisMsg24 ("HE2K5MA`58hTpL0000000000000", 2);
    
        auto csvRow = toCsvRow (msg);
        string[] cells = csvRow.split(",");
        assert (cells.length == aisCsvCols.length);

        // Since we know the fields in type 24 B...
        auto nonEmptyCells = cells.filter !(c => c.length > 0) .array;
        //assert (nonEmptyCells.length == 6);
        assert (nonEmptyCells.length == 5);

        // Get the member of 'cells' matching col header named 'colName'
        auto colVal = delegate string(in string colName) {
            auto idx = aisCsvCols.countUntil (colName);
            return cells [idx]; };

        assert (colVal("type") == "24");
        assert (colVal("repeat") == "1");
        assert (colVal("mmsi") == "338085237");
        assert (colVal("partno") == "0");
        assert (colVal("shipname") == "\"ZARLING\"");
    }

    // Type 3 with invalid turn
    {
        auto msg = AisMsg1n2n3 ("33J=hV0OhmNv;lbQ<CA`sW>T00rQ", 0);

        auto csvRow = toCsvRow (msg);
        string[] cells = csvRow.split(",");
        assert (cells.length == aisCsvCols.length);

        // Get the member of 'cells' matching col header named 'colName'
        auto colVal = delegate string(in string colName) {
            auto idx = aisCsvCols.countUntil (colName);
            return cells [idx]; };

        assert (colVal("type") == "3");
        assert (colVal("mmsi") == "228815000");
        assert (colVal("turn") == "");
    }

    // Type 1 with valid turn
    {
        auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);

        auto csvRow = toCsvRow (msg);
        string[] cells = csvRow.split(",");
        assert (cells.length == aisCsvCols.length);

        // Get the member of 'cells' matching col header named 'colName'
        auto colVal = delegate string(in string colName) {
            auto idx = aisCsvCols.countUntil (colName);
            return cells [idx]; };

        assert (colVal("mmsi") == "477553000");
        assert (colVal("turn") == "0");
    }
}
