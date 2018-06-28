//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.geo;
import std.math;

//  --------------------------------------------------------------------------
//  Type predicate: does a message have a lat/lon?

enum bool isPositional(T) = is(typeof(T.lat)) && is(typeof(T.lon));

unittest {
    import aisutil.dlibaiswrap;
    static assert (isPositional!AisMsg1n2n3);
    static assert (! isPositional!AisMsg5);
}


//  ----------------------------------------------------------------------
//  Basic Geo Position type - holds degrees

struct GeoPos {
    double lat;
    double lon;
}


//  --------------------------------------------------------------------------
//  Holder for a geospatial bounding box

struct GeoBounds {
    double minLat, maxLat;
    double minLon, maxLon;

    static GeoBounds withWorld() {
        GeoBounds res = { minLat: -90, maxLat: 90, minLon: -180, maxLon: 180 };
        return res; }

    bool contains(T) (in ref T obj) const if(isPositional!T) {
        return    minLat <= obj.lat && obj.lat <= maxLat 
               && minLon <= obj.lon && obj.lon <= maxLon;
    }
}

unittest {
    auto gb = GeoBounds.withWorld();
    struct GeoPos{double lat, lon;}
    static assert (isPositional!GeoPos);
    GeoPos pos;
    
    pos = GeoPos (3, 3);
    assert (gb.contains (pos));
    pos = GeoPos (91, 3);
    assert (! gb.contains (pos));
    pos = GeoPos (3, 181);
    assert (! gb.contains (pos));
    pos = GeoPos (-91, 3);
    assert (! gb.contains (pos));
    pos = GeoPos (3, 181);
    assert (! gb.contains (pos));
}


//  ----------------------------------------------------------------------
//  Distances in metres between things (haversine)

private immutable earth_radius_metres = 6367444.7;

double distMetres (GeoPos gp1, GeoPos gp2) {
    return distMetres (gp1.lat, gp1.lon,
                       gp2.lat, gp2.lon);
}

double distMetres (double lat1, double lon1,
                   double lat2, double lon2) {
    return earth_radius_metres *
        arcLengthRadsRads (degToRad(lat1), degToRad(lon1),
                           degToRad(lat2), degToRad(lon2));
}

// Takes radians for positions, and returns radians.
private double arcLengthRadsRads (double lat1, double lon1,
                                  double lat2, double lon2) {
    auto latArc = lat1 - lat2;
    auto lonArc = lon1 - lon2;

    auto latH = sin (latArc * 0.5);
    latH *= latH;

    auto lonH = sin (lonArc * 0.5);
    lonH *= lonH;

    auto tmp = cos (lat1) * cos (lat2);
    return 2.0 * asin (sqrt(latH + tmp * lonH));
}

// Degrees to radians
private double degToRad( double degs ) {
    return degs * (PI / 180.0);
}
