//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.ais;
import std.variant;
import aisutil.dlibaiswrap;

// General views into AIS data


//  --------------------------------------------------------------------------
//  AIS message trait

enum bool isAisMsg(T) =    is(T == AisMsg1n2n3) || is(T == AisMsg5)
                        || is(T == AisMsg18)    || is(T == AisMsg19)
                        || is(T == AisMsg24)    || is(T == AisMsg27);


//  --------------------------------------------------------------------------
//  Tagged-union type for holding any AIS message

alias AnyAisMsg = Algebraic!(AisMsg1n2n3, AisMsg5, AisMsg18, AisMsg19,
                             AisMsg24, AisMsg27);

// Helper, to get its mmsi easily
int mmsi (in ref AnyAisMsg msg) {
    return msg.visit!((in ref AisMsg1n2n3 m) => m.mmsi,
                      (in ref AisMsg5     m) => m.mmsi,
                      (in ref AisMsg18    m) => m.mmsi,
                      (in ref AisMsg19    m) => m.mmsi,
                      (in ref AisMsg24    m) => m.mmsi,
                      (in ref AisMsg27    m) => m.mmsi)();
}

// Which members have a position?
bool isPositional (AnyAisMsg msg) {
    return msg.visit!(
        (AisMsg1n2n3 m) => true,
        (AisMsg5     m) => false,
        (AisMsg18    m) => true,
        (AisMsg19    m) => true,
        (AisMsg24    m) => false,
        (AisMsg27    m) => true
    );
}


//  --------------------------------------------------------------------------
//  Version holding a possible-timestamp too

import std.typecons;

struct AnyAisMsgPossTS {
    AnyAisMsg msg;
    Nullable!int possTS;

    int mmsi () const {
        return msg.mmsi;
    }
}


//  ----------------------------------------------------------------------
//  Utils for investigating whether an AnyAisMsg has a speed val, and getting it

bool hasSpeed (AnyAisMsg msg) {
    return msg.visit!(
        (AisMsg1n2n3 m) => true,
        (AisMsg5     m) => false,
        (AisMsg18    m) => true,
        (AisMsg19    m) => true,
        (AisMsg24    m) => false,
        (AisMsg27    m) => true,
    );
}

double speed (AnyAisMsg msg) {
    import std.exception, core.exception;
    assert (msg.hasSpeed);
    return msg.visit!(
        (AisMsg1n2n3 m) => m.speed,
        (AisMsg5     m) {
            enforce!AssertError (false, "AisMsg5 does not have speed field");
            return -1; },  // placate compiler
        (AisMsg18    m) => m.speed,
        (AisMsg19    m) => m.speed,
        (AisMsg24    m) {
            enforce!AssertError (false, "AisMsg24 does not have speed field");
            return -1; },  // placate compiler
        (AisMsg27    m) => m.speed,
    );
}

unittest {
    auto msg = AnyAisMsg (AisMsg1n2n3 ("177KQJ5000G?tO`K>RA1wUbN0TKH", 0));
    assert (msg.hasSpeed ());
    assert (msg.speed == 0.0);
}


//  --------------------------------------------------------------------------
//  Parser for AnyAisMsg (if you want it)

class UnparseableMessageTypeException : Exception {
    // TODO better member vars etc
    import std.conv;
    this (int msgType) {super (to!string(msgType));}
}

AnyAisMsg parseAnyAisMsg (int msgType, const(char)[] payload, size_t fillbits) {
    import aisutil.dlibaiswrap;
    
    if (msgType == 1 || msgType == 2 || msgType == 3) {
        return AnyAisMsg (AisMsg1n2n3 (payload, fillbits));
    } else
    if (msgType == 5) {
        return AnyAisMsg (AisMsg5 (payload, fillbits));
    } else
    if (msgType == 18) {
        return AnyAisMsg (AisMsg18 (payload, fillbits));
    } else
    if (msgType == 19) {
        return AnyAisMsg (AisMsg19 (payload, fillbits));
    } else
    if (msgType == 24) {
        return AnyAisMsg (AisMsg24 (payload, fillbits));
    } else
    if (msgType == 27) {
        return AnyAisMsg (AisMsg27 (payload, fillbits));
    } else {
        // TODO better exception
        throw new UnparseableMessageTypeException (msgType);
    }
}


//  ----------------------------------------------------------------------
//  AIS message wrapper converting some AIS special vals to nulls
//  
//    Behaves as the wrapped type, but changes lat, lon, speed, course, turn
//    and heading to Nullable's, holding null when the field contained one
//    of the sentinel values ('NA' or 'beyond range').
//    
//    This is only supposed to be used during output format generation

struct AisValueFixer(T) if(isAisMsg!T) {
    const T *_data;

    // Wraps a given object
    this (in ref T data) { _data = &data; }

    // By default, just behave as if the object on field ref
    auto opDispatch (string name) () {
        return __traits (getMember, _data, name);
    }

    // Override 'mmsi' func on AnyAisMsg above, which overrides opDispatch
    int mmsi () { return _data.mmsi; }

    // -- Expose most important sentinel-bearing valus as Nullable's
    //      TODO reduce the repetition with some templates

    static if (is(typeof(T.lat))) {
        Nullable!double lat () {
            if (_data.lat == 91.0)
                return Nullable!double.init;
            else
                return Nullable!double (_data.lat);
        }
    }
    static if (is(typeof(T.lon))) {
        Nullable!double lon () {
            if (_data.lon == 181.0)
                return Nullable!double.init;
            else
                return Nullable!double (_data.lon);
        }
    }
    static if (is(typeof(T.course))) {
        Nullable!double course () {
            if (_data.course == 360.0)
                return Nullable!double.init;
            else
                return Nullable!double (_data.course);
        }
    }
    static if (is(typeof(T.speed))) {
        Nullable!double speed () {
            if (_data.speed >= 102.2)  // 1023 is NA, 1022 is 'over range'
                return Nullable!double.init;
            else
                return Nullable!double (_data.speed);
        }
    }
    static if (is(typeof(T.turn))) {
        Nullable!double turn () {
            if (_data.turn_valid)
                return Nullable!double (_data.turn);
            else
                return Nullable!double.init;
        }
    }
    static if (is(typeof(T.heading))) {
        Nullable!double heading () {
            if (_data.heading == 511)
                return Nullable!double.init;
            else
                return Nullable!double (_data.heading);
        }
    }
}

// For type inference
auto aisValueFixer(T) (in ref T msg) if(isAisMsg!T) {
    return AisValueFixer!T (msg);
}

unittest {
    import aisutil.dlibaiswrap;
    import std.math;

    // All special vals valid
    {
        auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
        // {u'slot_timeout': 1L, u'sync_state': 1L, u'true_heading': 181L, u'utc_spare': 0L, u'sog': 0.0, u'rot': 0.0, u'nav_status': 5L, u'repeat_indicator': 0L, u'raim': False, u'id': 1L, u'utc_min': 54L, u'spare': 0L, u'cog': 51.0, u'timestamp': 15L, u'y': 47.58283333333333, u'x': -122.34583333333333, u'position_accuracy': 0L, u'utc_hour': 3L, u'rot_over_range': False, u'mmsi': 477553000L, u'special_manoeuvre': 0L}
        assert (msg.mmsi == 477553000);
        assert (msg.lat.approxEqual (47.58283333333333));
        assert (msg.turn_valid);
        assert (msg.turn.approxEqual (0));

        auto fixer = aisValueFixer (msg);
        assert (fixer.mmsi == 477553000);
        assert (fixer.lat.approxEqual (47.58283333333333));
        assert (fixer.turn_valid);
        assert (! fixer.turn.isNull);
        assert (fixer.turn.approxEqual (0));
        assert (fixer.speed.approxEqual (0.0));
        assert (fixer.course.approxEqual (51.0));
    }

    // Turn invalid
    {
        auto msg = AisMsg1n2n3("33J=hV0OhmNv;lbQ<CA`sW>T00rQ", 0);
        // {u'slot_increment': 234L, u'sync_state': 0L, u'true_heading': 231L, u'sog': 5.300000190734863, u'slots_to_allocate': 0L, u'rot': 720.0032348632812, u'nav_status': 0L, u'repeat_indicator': 0L, u'raim': False, u'id': 3L, u'spare': 0L, u'keep_flag': True, u'cog': 228.60000610351562, u'timestamp': 18L, u'y': 58.007583333333336, u'x': -14.377565, u'position_accuracy': 0L, u'rot_over_range': True, u'mmsi': 228815000L, u'special_manoeuvre': 0L}
        assert (msg.mmsi == 228815000);
        assert (msg.lat.approxEqual (58.007583333333336));
        assert (! msg.turn_valid);

        auto fixer = aisValueFixer (msg);
        assert (fixer.turn .isNull);
        assert (fixer.speed.approxEqual (5.300000190734863));
        assert (fixer.course.approxEqual (228.60000610351562));
        assert (fixer.mmsi == 228815000);
        assert (fixer.lat.approxEqual (58.007583333333336));
    }

    // Speed and course invalid
    {
        auto msg = AisMsg1n2n3 ("13P<sFE0?w05qr@MfL;>42<805H0", 0);
        // {u'slot_timeout': 1L, u'sync_state': 0L, u'true_heading': 70L, u'utc_spare': 0L, u'sog': 102.30000305175781, u'rot': 0.0, u'nav_status': 5L, u'repeat_indicator': 0L, u'raim': False, u'id': 1L, u'utc_min': 0L, u'spare': 0L, u'cog': 360.0, u'timestamp': 4L, u'y': 51.9493, u'x': 1.2899333333333334, u'position_accuracy': 0L, u'utc_hour': 11L, u'rot_over_range': False, u'mmsi': 235092825L, u'special_manoeuvre': 0L}
        assert (msg.mmsi == 235092825);

        auto fixer = aisValueFixer (msg);
        assert (fixer.mmsi == 235092825);
        assert (! fixer.turn .isNull);
        assert (fixer.course .isNull);
        assert (fixer.speed .isNull);
        assert (fixer.heading == 70);
    }

    // Position, course and speed invalid
    {
        auto msg = AisMsg1n2n3 ("13M@JAP0?w<tSF0l4Q@>42Ap0PRo", 0);
        // {u'slot_timeout': 0L, u'sync_state': 1L, u'true_heading': 72L, u'sog': 102.30000305175781, u'rot': 0.0, u'nav_status': 0L, u'repeat_indicator': 0L, u'raim': False, u'slot_offset': 2231L, u'id': 1L, u'spare': 0L, u'cog': 360.0, u'timestamp': 60L, u'y': 91.0, u'x': 181.0, u'position_accuracy': 0L, u'rot_over_range': False, u'mmsi': 232004166L, u'special_manoeuvre': 0L}
        assert (msg.mmsi == 232004166);

        auto fixer = aisValueFixer (msg);
        assert (fixer.mmsi == 232004166);
        assert (fixer.lat.isNull);
        assert (fixer.lon.isNull);
        assert (fixer.speed.isNull);
        assert (fixer.course.isNull);
        assert (fixer.turn == 0.0);
    }

    // Heading invalid
    {
        auto msg = AisMsg1n2n3 ("15N1u<PP1FJuvSRHOE6QIwwh0HQ6", 0);
        // {u'slot_timeout': 6L, u'sync_state': 0L, u'true_heading': 511L, u'sog': 8.600000381469727, u'rot': -731.386474609375, u'nav_status': 0L, u'repeat_indicator': 0L, u'raim': False, u'id': 1L, u'slot_number': 2118L, u'spare': 0L, u'cog': 35.900001525878906, u'timestamp': 56L, u'y': 42.79855, u'x': -70.346905, u'position_accuracy': 0L, u'rot_over_range': True, u'mmsi': 367033650L, u'special_manoeuvre': 0L}
        assert (msg.mmsi == 367033650);
        assert (msg.heading == 511);

        auto fixer = aisValueFixer (msg);
        assert (fixer.heading .isNull);
    }
}
