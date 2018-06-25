//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.json;
import std.json, std.typecons, std.range, std.algorithm, std.variant;
import aisutil.ext.libaiswrap, aisutil.ais, aisutil.dlibaiswrap;

// Turning AIS message structs into JSON objects,
// ready for writing to disk.


//  --------------------------------------------------------------------------
//  Allowed json keys to write - the member vars of all the AIS msgs,
//  plus "tagblock_timestamp"


private immutable string[] ignoredFields = ["parse_error", "turn_valid"];

private immutable string[] allJsonKeys = "tagblock_timestamp"
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
//  Making JSON objects

// Main set value path
private void setJsonMember (ref JSONValue js, in string key, in int val) {
    js[key] = JSONValue (val);
}
private void setJsonMember (ref JSONValue js, in string key, in double val) {
    js[key] = JSONValue (val);
}
private void setJsonMember (ref JSONValue js, in string key, in string val) {
    js[key] = JSONValue (val);
}

// Special case for c-style strings
private void setJsonMember(ref JSONValue js, in string key, const(char)* val) {
    import std.string;
    js[key] = JSONValue(val.fromStringz);
}

// Set value for nullables (sets to null if isNull)
private void setJsonMember (ref JSONValue js, in string key,
                            in Nullable!int val) {
    if (val.isNull) js[key] = null;
    else            js[key] = JSONValue (val.get);
}
private void setJsonMember (ref JSONValue js, in string key,
                            in Nullable!double val) {
    if (val.isNull) js[key] = null;
    else            js[key] = JSONValue (val.get);
}
private void setJsonMember (ref JSONValue js, in string key,
                            in Nullable!string val) {
    if (val.isNull) js[key] = null;
    else            js[key] = JSONValue (val.get);
}


// -- Top level driver: make a json object from an AIS object

// AnyAisMsg wrapper
JSONValue toJsonVal (in ref AnyAisMsg msg,
                     Nullable!int tagblockTimestamp = Nullable!int.init) {
    return msg.visit!(
        (in ref AisMsg1n2n3 m) => toJsonVal (m, tagblockTimestamp),
        (in ref AisMsg5     m) => toJsonVal (m, tagblockTimestamp),
        (in ref AisMsg18    m) => toJsonVal (m, tagblockTimestamp),
        (in ref AisMsg19    m) => toJsonVal (m, tagblockTimestamp),
        (in ref AisMsg24    m) => toJsonVal (m, tagblockTimestamp),
        (in ref AisMsg27    m) => toJsonVal (m, tagblockTimestamp)
    );
}

// Message type taking template version
JSONValue toJsonVal(T)(in T obj,
                       Nullable!int tagblockTimestamp = Nullable!int.init)
    if(isAisMsg!T)
{
    JSONValue res;
    auto fixer = aisValueFixer (obj);

    static foreach (key; allJsonKeys) {
        // tbts is special
        static if (key == "tagblock_timestamp") {
            if (tagblockTimestamp.isNull) {
                // pass
            } else {
                res[key] = tagblockTimestamp.get;
            }
        } else
        static if (__traits (hasMember, obj, key)) {
            // Every other present field works in this way

            // Check if a has_xxx fun is present, and if so only fetch datum
            // if it returns true
            static if (__traits (hasMember, obj, "has_" ~ key)) {
                if (__traits (getMember, obj, "has_" ~ key))
                    setJsonMember (res, key, __traits (getMember, fixer, key));
            } else {
                setJsonMember (res, key, __traits (getMember, fixer, key));
            }
        } else {
            // pass (if no such member)
        }
    }

    return res;
}

// -- Tests

unittest {
    import aisutil.dlibaiswrap;

    // Msg 1, with no tagblock timestamp
    {
        auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
        auto js = toJsonVal(msg);

        assert (js["mmsi"].integer == 477553000);
        import std.math;
        assert (js["lat"].floating.approxEqual(47.58283333333333));
        assert (js["lon"].floating.approxEqual(-122.34583333333333));
        assert (js["turn"].floating.approxEqual(0));
        
        assert (! ("xxxxxx" in js));
        assert (! ("tagblock_timestamp" in js));
    }

    // Same but with tbts
    {
        auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
        Nullable!int ts = 12345;
        auto js = toJsonVal(msg, ts);

        assert (js["mmsi"].integer == 477553000);
        assert (js["tagblock_timestamp"].integer == 12345);
    }

    // Msg 5
    {
        auto msg = AisMsg5("55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::" ~
                           "4A80?4i@E531@0000000000000", 2);
        auto js = toJsonVal(msg);

        assert (js["destination"].str == "SEATTLE");
        assert (js["shipname"].str == "MT.MITCHELL");
        assert (js["shiptype"].integer == 99);
    }

    // Msg24a
    {
        auto msg = AisMsg24("HE2K5MA`58hTpL0000000000000", 2);
        auto js = toJsonVal (msg, Nullable!int(121212));

        assert (js["shipname"].str == "ZARLING");
        assert (js["mmsi"].integer == 338085237);
        assert (js["partno"].integer == 0);
        assert (js["tagblock_timestamp"].integer == 121212);
        assert ("mmsi" in js);
        assert (! ("callsign" in js));
    }

    // Msg24b
    {
        auto msg = AisMsg24("H3pro:4q3?=1B0000000000P7220", 0);
        auto js = toJsonVal (msg);

        assert (js["vendorid"].str == "COMAR");
        assert (js["to_starboard"].integer == 2);
        assert (js["shiptype"].integer == 57);
        assert (! ("shipname" in js));
    }

    // Msg3 with invalid turn
    {
        auto msg = AisMsg1n2n3("33J=hV0OhmNv;lbQ<CA`sW>T00rQ", 0);
        auto js = toJsonVal (msg);

        assert (js["mmsi"].integer == 228815000);
        assert (js["turn"].isNull);
    }
}
