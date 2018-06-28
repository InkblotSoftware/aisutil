//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.geotracks;
import aisutil.ais, aisutil.geo, aisutil.dlibaiswrap;
import std.range, std.algorithm, std.variant, std.exception, std.math,
       std.typecons, std.stdio;


//  ======================================================================
//  == GeoTrack tracking and management
//  ==
//  ==   Sometimes more than one vessel broadcasts under the same MMSI. This
//  ==   manifests as the vessel's track 'teleporting' back and forth between
//  ==   (usually) unrelated geographic locations, as the transmitters
//  ==   alternatively broadcast messages.
//  ==
//  ==   This can be quite annoying in a number of cases, so this module
//  ==   implements a disambiguation mechanism. It's very simple: if a vessel
//  ==   would have to transport at more than 100mps to get between two messages
//  ==   we say they came from separate ships.
//  ==
//  ==   Unfortunately, data that isn't provided in strictlytimestamp-ascending
//  ==   order often causes problems for this, as it's easy for suprious
//  ==   connections appear better than real ones to the detector. If your data
//  ==   isn't timestamp ordered then you're usually best off taking the
//  ==   geotrack ids with a large pinch of salt.
//  ==
//  ==   Each GeoTrackID is associated with an MMSI, and is allocated upwards
//  ==   from 1 as the first value. These can be passed as opaque values to the
//  ==   CSV and JSON making modules.
//  ==
//  ==   Note that non-positional messages cannot have a GeoTrackID, since they
//  ==   don't have a position. You're suggested to use a Nullable!GeoTrackID
//  ==   as a type in interfaces to allow for this.
//  ==
//  ==   Further, since timestamps are required to do any kind of GeoTrack
//  ==   analysis, you have to silently ignore timestamp-free messages. The
//  ==   interfaces exposed in this module don't allow null timestamps.
//  ==
//  ==   You want to use the GeoTrackFinder struct, and stream messages through
//  ==   it, collecting the assigned GeoTrackIDs as you go.
//  ======================================================================


//  ----------------------------------------------------------------------
//  Types and constants

private alias Mmsi = int;

// Any between-track-message-pair speed above this opens a new geotrack
private immutable max_valid_geotrack_speed_mps = 100.0;


//  ------------------------------------------------------------
//  GeoTrack ID (usually treat this as opaque)

struct GeoTrackID {
    private int _value;
    alias _value this;
    int value () { return _value; }
}


//  ----------------------------------------------------------------------
//  Data representing one GeoTrack for one MMSI

private struct GeoTrackData {
    GeoTrackID gtid;
    Mmsi       mmsi;
    GeoPos lastMsgPos;
    int lastMsgTimestamp;

    // Does the provided message correlate with this geotrack?
    bool isValidWithMsg (AnyAisMsg msg, int timestamp) {
        // // Left in to assist debugging:
        // writeln ("isValidWithMsg() called...");
        // writeln ("gtd: ", this);
        // writeln ("msg: ", msg, " ", timestamp);
        // writeln ("secs: ", timestamp - lastMsgTimestamp);
        // writeln ("metres: ", msg.toGeoPos().distMetres (lastMsgPos));
        // writeln ("speed: ", speedMpsToTrack (this, msg, timestamp));

        // Allow tolerance, as receivers sometimes mark different messages
        // with same timestamp
        if (lastMsgTimestamp == timestamp)
            return lastMsgPos.distMetres(msg.toGeoPos()) < 20.0;
        else
            return    speedMpsToTrack (this, msg, timestamp)
                   <= max_valid_geotrack_speed_mps;
    }
}

// How fast would a vessel have to travel from a message to the GT's last postime?
private double speedMpsToTrack (GeoTrackData gtd, AnyAisMsg msg, int timestamp) {
    assert (msg.isPositional);
    double distance = gtd.lastMsgPos .distMetres (msg.toGeoPos());
    int seconds = abs (gtd.lastMsgTimestamp - timestamp);
    return distance / cast(double)seconds;
}

unittest {
    auto gtd = GeoTrackData (GeoTrackID(1), 1, GeoPos(1.1, 2.2), 1000);

    // Scratch msg
    auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);

    // Valid when msg at same pos (and time) as cur msg
    msg.lat = 1.1;
    msg.lon = 2.2;
    assert (gtd.isValidWithMsg (AnyAisMsg(msg), 1000));
    assert (gtd.isValidWithMsg (AnyAisMsg(msg), 1010));

    // Valid when msg very slighly away from cur msg and at same or similar time
    msg.lat = 1.1000001;
    msg.lon = 2.2000001;
    assert (gtd.isValidWithMsg (AnyAisMsg(msg), 1000));
    assert (gtd.isValidWithMsg (AnyAisMsg(msg), 1010));

    // Not valid when message too far away at too close time
    msg.lat = 10.0;
    msg.lon = 20.0;
    assert (! gtd.isValidWithMsg (AnyAisMsg(msg), 1000));
    assert (! gtd.isValidWithMsg (AnyAisMsg(msg), 1010));
}


//  ----------------------------------------------------------------------
//  Store for all GeoTracks known for a single MMSI

private struct OneMmsiGeoTracks {
    private Mmsi _mmsi;
    private GeoTrackData[] _tracks;

    @disable this();
    this (Mmsi mmsi) { _mmsi = mmsi; }

    GeoTrackID put (in ref AnyAisMsg msg, int timestamp) {
        assert (msg.mmsi == _mmsi);
        assert (msg.isPositional());

        auto valids = _tracks.filter !(t => t.isValidWithMsg (msg, timestamp));
        
        if (valids.empty) {
            // Need to make a new GT
            auto gtid = GeoTrackID (cast(int)_tracks.length + 1);
            GeoTrackData newGT = { gtid: gtid, mmsi: _mmsi, lastMsgPos:
                                   msg.toGeoPos, lastMsgTimestamp: timestamp };
            _tracks ~= (newGT);
            return gtid;
            
        } else {
            // At least one GT exists and is valid. The one that's currently
            // closest to the message is probably the best match:
            GeoTrackData gtd = valids
                .minElement !(d => d.lastMsgPos.distMetres(msg.toGeoPos()));

            // Always update the 'geotrack last known message', even if the
            // new message is older than the current.
            // This helps with out-of-order input data.
            gtd.lastMsgPos = msg.toGeoPos;
            gtd.lastMsgTimestamp = timestamp;
            auto newTracks = _tracks
                .filter !(t => t.gtid != gtd.gtid)
                .array
                ~ gtd;
            _tracks = newTracks;

            return gtd.gtid;
        }
    }
}            


//  ------------------------------------------------------------
//  Tracker of messages that assigns geotrack ids to them
//  
//    Stream messages you get through this (assuming they're positional);
//    it'll assign them to geo tracks and keep itself up to date.

struct GeoTrackFinder {
    @disable this(this);

    // Map from MMSIs to all the GTs we currently know for them
    private OneMmsiGeoTracks[Mmsi] _knownGeoTracks;

    // Calc a GTID for a message, and update the interal store if necessary
    GeoTrackID put (AnyAisMsg msg, int timestamp) {
        enforce (msg.isPositional());
        Mmsi mmsi = msg.mmsi;

        if (mmsi !in _knownGeoTracks) {
            // First message seen for this MMSI
            auto kmgt = OneMmsiGeoTracks (mmsi);
            auto gtid = kmgt.put (msg, timestamp);
            _knownGeoTracks [mmsi] = kmgt;
            return gtid;
            
        } else {
            // Seen the MMSI before
            auto kmgt = mmsi in _knownGeoTracks;
            return kmgt.put (msg, timestamp);
        }
    }
}


//  ----------------------------------------------------------------------
//  Geo helpers

private GeoPos toGeoPos (AnyAisMsg msg) {
    assert (msg.isPositional());
    import core.exception;
    return msg.visit! (
        (AisMsg1n2n3 m) => GeoPos (m.lat, m.lon),
        (AisMsg5     m) { enforce!AssertError
                              (false, "AisMsg5 is not positional");
                          return GeoPos (0,0); },  // placate compiler
        (AisMsg18    m) => GeoPos (m.lat, m.lon),
        (AisMsg19    m) => GeoPos (m.lat, m.lon),
        (AisMsg24    m) { enforce!AssertError
                              (false, "AisMsg24 is not positional");
                          return GeoPos (0,0); },  // placate compiler
        (AisMsg27    m) => GeoPos (m.lat, m.lon)
    );
}


//  ----------------------------------------------------------------------
//  Tests

// Set 1
unittest {
    auto tracker = GeoTrackFinder ();

    auto basicMsg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
    // {u'slot_timeout': 1L, u'sync_state': 1L, u'true_heading': 181L, u'utc_spare': 0L, u'sog': 0.0, u'rot': 0.0, u'nav_status': 5L, u'repeat_indicator': 0L, u'raim': False, u'id': 1L, u'utc_min': 54L, u'spare': 0L, u'cog': 51.0, u'timestamp': 15L, u'y': 47.58283333333333, u'x': -122.34583333333333, u'position_accuracy': 0L, u'utc_hour': 3L, u'rot_over_range': False, u'mmsi': 477553000L, u'special_manoeuvre': 0L}
    immutable startTime = 10000;
    
    // Make the messagea you want based on basicMsg
    auto makeMsg = delegate AnyAisMsg (int mmsi, double dLat, double dLon) {
        AisMsg1n2n3 dup = basicMsg;
        dup.mmsi = mmsi;
        dup.lat += dLat;
        dup.lon += dLon;
        return AnyAisMsg (dup);
    };

    // Track data we use in the tests

    immutable mmsi1_gt1_m1 = makeMsg (111, 0, 0);
    immutable mmsi1_gt1_m2 = makeMsg (111, 0.001, 0.001);
    immutable mmsi1_gt1_m3 = makeMsg (111, 0.002, 0.002);

    immutable mmsi1_gt2_m1 = makeMsg (111, 10, 10);
    immutable mmsi1_gt2_m2 = makeMsg (111, 10.001, 10.001);

    immutable mmsi2_gt1_m1 = makeMsg (222, 20, 20);
    immutable mmsi2_gt1_m2 = makeMsg (222, 20.001, 20.001);

    immutable mmsi2_gt2_m1 = makeMsg (222, 44.0, 44.0);

    // Sanity check we've got the dists right
    assert ((  mmsi1_gt1_m1.toGeoPos().distMetres (mmsi1_gt1_m2.toGeoPos())
             / 10.0)
            <= 100);

    // Do the tests
    
    GeoTrackID gtid;

    gtid = tracker.put (mmsi1_gt1_m1, startTime);
    assert (gtid == 1);
    gtid = tracker.put (mmsi1_gt1_m1, startTime);  // same message
    assert (gtid == 1);
    gtid = tracker.put (mmsi1_gt1_m2, startTime + 10);
    assert (gtid == 1);

    gtid = tracker.put (mmsi2_gt1_m1, startTime + 20);
    assert (gtid == 1);

    gtid = tracker.put (mmsi1_gt2_m1, startTime + 30);
    assert (gtid == 2);
    gtid = tracker.put (mmsi1_gt2_m2, startTime + 40);
    assert (gtid == 2);

    gtid = tracker.put (mmsi2_gt1_m2, startTime - 20);
    assert (gtid == 1);

    gtid = tracker.put (mmsi2_gt2_m1, startTime + 5);
    assert (gtid == 2);

    gtid = tracker.put (mmsi1_gt1_m3, startTime - 10);
    assert (gtid == 1);
}

// Set 2
unittest {
    struct GPT {
        double lat, lon;
        int ts;
        int gtid;
    }
    void assertDataOK (GPT[] dats) {
        auto geoTracker = GeoTrackFinder ();
        foreach (d; dats) {
            // Scratch msg
            auto msg = AisMsg1n2n3 ("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
            msg.lat = d.lat;
            msg.lon = d.lon;

            auto gtid = geoTracker.put (AnyAisMsg(msg), d.ts);
            assert (gtid == d.gtid);
        }
    }

    assertDataOK ([ GPT(52.458378, 4.595007,1491022031, 1),
                    GPT(52.458385, 4.595017,1491025600, 1),
                    GPT(52.458380, 4.594980,1491029220, 1),
                    GPT(50.337770,-4.146713,1491029225, 2),
                    GPT(52.452762, 4.256542,1491032757, 1),
                    GPT(50.345888,-4.145508,1491032939, 2),
                    GPT(52.459970, 4.453907,1491036380, 1),
                    GPT(50.342608,-4.148375,1491036518, 2),
                    GPT(52.458377, 4.595043,1491040075, 1),
                    GPT(50.364493,-4.152170,1491040077, 2), 
                    GPT(50.337438,-4.146317,1491043621, 2),
                    GPT(52.458370, 4.594993,1491043635, 1,) ]);

    assertDataOK ([ GPT(50.80812, -1.118797, 1464426048, 1),
                    GPT(50.77857, -1.222053, 1464426105, 2),
                    GPT(50.77857, -1.222053, 1464426105, 2), ]);  // identical

    assertDataOK ([ GPT(52.84167, 5.671667, 1491262018, 1),
                    GPT(52.84142, 5.671337, 1491256053, 1),
                    GPT(52.43167, 4.735000, 1491301910, 1),
                    GPT(52.47020, 4.619287, 1491310079, 1), ]);
}
