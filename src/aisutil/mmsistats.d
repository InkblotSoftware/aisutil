//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.mmsistats;
import std.range, std.algorithm, std.exception, std.typecons, std.string, std.stdio;
import aisutil.shiptypes, aisutil.csv, aisutil.ais;

// Store for static data and general statistics about all MMSIs.
// 
// The idea is that you pass a series of decoded messages to an
// MmsiStatsBucket, and it maintains an MmsiStats value for each MMSI
// as new information passes by. We also keep a count of messages for
// each MMSI.
//
// You can query for this information at any point; we use it at the end
// to make a global "input MMSIs" csv.
//
// Note that if the Bucket gets two conflicting values for a field from
// the same MMSI, it keeps the first one it sees.


//  --------------------------------------------------------------------------
//  Data for one MMSI

struct MmsiStats {
    this(int mmsi) {this.mmsi = mmsi;}
    // Or more explicitly
    static MmsiStats withMmsi (int mmsi) { return MmsiStats(mmsi); }
    
    int mmsi;
    int numMsgs;
    
    Nullable!int    shiptype;
    Nullable!string shipname;
    Nullable!int    shiplen;

    bool hasShiptype() const {return !shiptype.isNull;}
    bool hasShipname() const {return !shipname.isNull;}
    bool hasShiplen () const {return !shiplen .isNull;}

    string toString() const {
        import std.conv;
        return format("(MmsiStats)(mmsi: %d, numMsgs: %d, " ~
                      "shiptype: %s, shipname: %s, shiplen: %s)",
                      mmsi, numMsgs,
                      shiptype.isNull ? "[shiptype=null]" : to!string(shiptype),
                      shipname.isNull ? "[shipname=null]" : shipname.get,
                      shiplen .isNull ? "[shiplen=null]"  : to!string(shiplen));
    }
}


//  --------------------------------------------------------------------------
//  Store for data on all MMSIs - feed this a stream of messages

struct MmsiStatsBucket {
    private MmsiStats[int] _data;
    
    // Update any possible missing stats from the given message.
    // Returns true iff new data was added to the bucket from it
    // (not just incrementing the message count)
    bool updateMissing (in ref AnyAisMsg msg) {
        import std.variant;
        return msg.visit!((m => updateMissing(m)));
    }
    bool updateMissing(T) (in ref T msg) if(isAisMsg!T) {
        return updateMissing_h (msg);
    }
    version (unittest) {
        // So we can test with C_AisMsgXXX structs
        bool updateMissing_force(T) (in ref T msg) {
            return updateMissing_h (msg);
        }
    }
    private bool updateMissing_h(T) (in ref T msg) {
        auto stats = _data.get (msg.mmsi, MmsiStats.withMmsi(msg.mmsi));
        immutable origStats = stats;
        ++stats.numMsgs;

        // Shiptype
        if (! stats.hasShiptype) {
            static if (is(typeof(T.shiptype))) {
                static if (is(typeof(T.has_shiptype))) {
                    if (msg.has_shiptype)
                        stats.shiptype = msg.shiptype;
                } else {
                    stats.shiptype = msg.shiptype;
                }
            }
        }
        
        // Shipname
        if (! stats.hasShipname) {
            static if (is(typeof(T.shipname))) {
                static if (is(typeof(T.has_shipname))) {
                    if (msg.has_shipname)
                        stats.shipname = msg.shipname.fromStringz.idup;
                } else {
                    stats.shipname = msg.shipname.fromStringz.idup;
                }
            }
        }

        // Ship length
        if (! stats.hasShiplen) {
            static if (is(typeof(T.to_bow)) && is(typeof(T.to_stern))) {
                // TODO poss handle situation where only one has a has_xxx?
                static if (is(typeof(T.has_to_bow)) && is(typeof(T.has_to_stern))) {
                    if (msg.has_to_bow && msg.has_to_stern)
                        stats.shiplen = msg.to_bow + msg.to_stern;
                } else
                    stats.shiplen = msg.to_bow + msg.to_stern;
            }
        }

        _data [msg.mmsi] = stats;
        return    stats.shiptype != origStats.shiptype
               || stats.shipname != origStats.shipname
               || stats.shiplen  != origStats.shiplen;
    }

    bool contains (int mmsi) const {return (mmsi in _data) != null;}

    MmsiStats opIndex (int mmsi) {
        if (mmsi in _data) {
            return _data[mmsi];
        } else {
            _data [mmsi] = MmsiStats.withMmsi (mmsi);
            return opIndex (mmsi); }
    }

    // Total number of messages seen by bucket
    int countAllMessages() const {
        import std.algorithm;
        return _data.values().map!(ms => ms.numMsgs).sum();
    }

    // Writes the contents of the bucket as a csv file
    void writeCsvFile(in string filePath) const {
        import std.stdio;
        auto f = File(filePath, "w");
        f.writeln("mmsi,message_count,first_broadcast_shipname," ~
                  "first_broadcast_shiptype,first_broadcast_shiptype_asstring," ~
                  "ship_length_metres");
        foreach (stats; _data.byValue) {
            f.write (stats.mmsi.csvValStr(), ",");
            f.write (stats.numMsgs.csvValStr(), ",");

            if (stats.hasShipname)
                f.write (stats.shipname.csvValStr(), ",");
            else
                f.write (",");

            if (stats.hasShiptype) {
                f.write (stats.shiptype.csvValStr(), ",",
                         stats.shiptype.shiptypeStringForCode.csvValStr(), ",");
            } else {
                f.write(",", ",");
            }

            if (stats.hasShiplen) {
                f.write (stats.shiplen.csvValStr(), ",");
            } else {
                f.write (",");
            }
            
            f.write("\n");
        }
    }
}

unittest {
    import aisutil.ext.libaiswrap;
    auto bucket = MmsiStatsBucket();
    bool changed;  // did the vessel static stats change
    
    auto msg1 = C_AisMsg5();
    msg1.mmsi = 111;
    msg1.shiptype = 8888;
    msg1.shipname = "my_ship_name".dup.ptr;
    changed = bucket.updateMissing_force(msg1);
    assert (changed);

    auto msg2 = C_AisMsg1n2n3();
    msg2.mmsi = 222;
    changed = bucket.updateMissing_force(msg2);
    assert (! changed);

    // This one's data is ignored, as msg1 already had the sn/st data
    auto msg3 = C_AisMsg5();
    msg3.mmsi = 111;
    msg3.shiptype = 555555555;
    msg3.shipname = "other_ship_name".dup.ptr;
    changed = bucket.updateMissing_force (msg3);
    assert (!changed);

    assert (bucket[111].numMsgs == 2);
    assert (bucket[222].numMsgs == 1);

    assert (  bucket[111].hasShiptype);
    assert (! bucket[222].hasShiptype);

    assert (  bucket[111].hasShipname);
    assert (! bucket[222].hasShipname);
    
    assert (bucket[111].shiptype == 8888);
    assert (bucket[111].shipname == "my_ship_name");

    assert (bucket.countAllMessages() == 3);
}
