module aisutil.csv;
import std.string, std.range, std.algorithm, std.conv, std.typecons;
import aisutil.ext.libaiswrap, aisutil.ais;


// Functions to generate CSV strings, particularly for AIS messages
// ================================================================
//
// The format created is compatible with the variant Excel uses.


//  --------------------------------------------------------------------------
//  Generating CSV value strings (for individual fields)
//    NB strings are escaped and surrounded by '"' quotes

string csvValStr (string str) {
    return "\"" ~ str.replace("\"", "\"\"") ~ "\"";
}
string csvValStr (const(char)* str) { return (to!string(str)).csvValStr; }

string csvValStr (int    num) { return to!string(num); }
string csvValStr (double num) { return "%.18g".format(num); } //to!string(num); }
string csvValStr (bool   val) { return to!string(val); }

string csvValStr(T) (Nullable!T obj) {
    return obj.isNull ? "" : csvValStr(obj.get);
}

unittest {
    assert (" some\"string".csvValStr == "\" some\"\"string\"");
    assert (" some\"string".ptr.csvValStr == "\" some\"\"string\"");
    assert (123.csvValStr == "123");
    // Correct value on linux x64 dmd without optimisation.
    // Patches welcome if wrong on other setups.
    assert (csvValStr (123.123) == "123.123000000000005");
}


//  --------------------------------------------------------------------------
//  Names of all the fields used in AIS messages, plus a tb timestamp
//    These are used to generate headers and uniform rows for AIS objects, the
//    latter by static reflection

private immutable string[] aisCsvCols = "tagblock_timestamp"
                                        ~
                                        (  [__traits(allMembers, C_AisMsg1n2n3)]
                                         ~ [__traits(allMembers, C_AisMsg5)]
                                         ~ [__traits(allMembers, C_AisMsg18)]
                                         ~ [__traits(allMembers, C_AisMsg19)]
                                         ~ [__traits(allMembers, C_AisMsg24)]
                                         ~ [__traits(allMembers, C_AisMsg27)])
                                            .dup.sort.uniq.array;


//  --------------------------------------------------------------------------
//  Header row for AIS message CSVs

string csvHeader() {
    return aisCsvCols.join(",");
}


//  --------------------------------------------------------------------------
//  Making CSV rows from AIS messages
//    Where a field doesn't exist in the passed AisMsg struct we write an
//    empty cell

string toCsvRow(T)(in T obj) if(isAisMsg!T) {
    return toCsvRow!T(obj, Nullable!int.init);
}
string toCsvRow(T)(in T obj, Nullable!int tagblockTimestamp) if(isAisMsg!T) {
    import std.conv;
    string res;
    bool doneFirst = false;

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
        static if (__traits(hasMember, obj, cn)) {
            // Every other present field is handled the same way
            
            // check for a has_xxx member, and if present only fetch if it rets true
            static if (__traits(hasMember, obj, "has_" ~ cn)) {
                if (__traits(getMember, obj, "has_" ~ cn))
                    res ~= __traits(getMember, obj, cn).csvValStr();
            } else {
                res ~= __traits(getMember, obj, cn).csvValStr();
            }
        } else {
            // pass (if no such member)
        }
    }
    
    return res;
}

unittest {
    import aisutil.dlibaiswrap;
    
    // Type 24A
    auto msg = AisMsg24 ("HE2K5MA`58hTpL0000000000000", 2);
    
    auto csvRow = toCsvRow (msg);
    string[] cells = csvRow.split(",");
    assert (cells.length == aisCsvCols.length);

    // Since we know the fields in type 24 B...
    auto nonEmptyCells = cells.filter !(c => c.length > 0) .array;
    assert (nonEmptyCells.length == 6);

    // Get the member of 'cells' matching col header named 'colName'
    auto colVal = delegate string(in string colName) {
        auto idx = aisCsvCols.countUntil (colName);
        return cells [idx]; };

    assert (colVal("parse_error") == "0");
    assert (colVal("type") == "24");
    assert (colVal("repeat") == "1");
    assert (colVal("mmsi") == "338085237");
    assert (colVal("partno") == "0");
    assert (colVal("shipname") == "\"ZARLING\"");
}
