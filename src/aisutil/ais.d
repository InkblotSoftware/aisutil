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
