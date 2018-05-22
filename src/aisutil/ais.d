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
