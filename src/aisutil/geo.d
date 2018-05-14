module aisutil.geo;

//  --------------------------------------------------------------------------
//  Type predicate: does a message have a lat/lon?

enum bool isPositional(T) = is(typeof(T.lat)) && is(typeof(T.lon));

unittest {
    import aisutil.dlibaiswrap;
    static assert (isPositional!AisMsg1n2n3);
    static assert (! isPositional!AisMsg5);
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
