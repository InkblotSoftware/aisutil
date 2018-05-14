module aisutil.dlibaiswrap;
import std.stdio, std.traits, std.exception;
import aisutil.ext.libaiswrap;

// D-style wrapper for aisutil.ext.libaiswrap c bindings
//
// Note that each AIS message type's member 'XXX' may be accompanied by
// a guard member 'bool has_XXX()', which signals to clients whether they
// are allowed to read that member's value. This is used in static reflection
// during the JSON and CSV generation process. In practice only the type
// 24 A/B difference makes use of this functionality.


//  --------------------------------------------------------------------------
//  AisMsg1n2n3

struct AisMsg1n2n3 {
    C_AisMsg1n2n3 _data;
    alias _data this;

    this(T)(in T body, size_t padding) if(isSomeString!T) {
        import std.string, std.exception;
        _data = AisMsg1n2n3_make(body.toStringz, padding);
        enforce (_data.parse_error == 0,
                 format ("Message parse failed: %s - %s", body, padding));
    }

    ~this() {
        AisMsg1n2n3_destroyChildren(&_data);
    }

    this(this) {
        AisMsg1n2n3_postblit(&_data);
    }

    string toString() {
        import std.format;
        return format("[dlibsaiswrap.AisMsg1n2n3](%s)", _data);
    }
}

unittest {
    auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
    // {u'slot_timeout': 1L, u'sync_state': 1L, u'true_heading': 181L, u'utc_spare': 0L, u'sog': 0.0, u'rot': 0.0, u'nav_status': 5L, u'repeat_indicator': 0L, u'raim': False, u'id': 1L, u'utc_min': 54L, u'spare': 0L, u'cog': 51.0, u'timestamp': 15L, u'y': 47.58283333333333, u'x': -122.34583333333333, u'position_accuracy': 0L, u'utc_hour': 3L, u'rot_over_range': False, u'mmsi': 477553000L, u'special_manoeuvre': 0L}
    assert (msg.mmsi == 477553000);
    import std.math;
    assert (msg.lat.approxEqual(47.58283333333333));
    assert (msg.lon.approxEqual(-122.34583333333333));
    assert (msg.turn_valid);
    assert (msg.second == 15);
    assert (msg.course.approxEqual (51.0));
    assert (msg.heading.approxEqual (181.0));


    // Now test a message with an invalid turn value
    
    auto msg2 = AisMsg1n2n3("33J=hV0OhmNv;lbQ<CA`sW>T00rQ", 0);
    // {u'slot_increment': 234L, u'sync_state': 0L, u'true_heading': 231L, u'sog': 5.300000190734863, u'slots_to_allocate': 0L, u'rot': 720.0032348632812, u'nav_status': 0L, u'repeat_indicator': 0L, u'raim': False, u'id': 3L, u'spare': 0L, u'keep_flag': True, u'cog': 228.60000610351562, u'timestamp': 18L, u'y': 58.007583333333336, u'x': -14.377565, u'position_accuracy': 0L, u'rot_over_range': True, u'mmsi': 228815000L, u'special_manoeuvre': 0L}
    assert (! msg2.turn_valid);
    assert (msg2.mmsi == 228815000);
    import std.math;
    assert (msg2.lat.approxEqual (58.007583333333336));
}


//  --------------------------------------------------------------------------
//  AisMsg5

struct AisMsg5 {
    C_AisMsg5 _data;
    alias _data this;

    this(T)(in T body, size_t padding) if(isSomeString!T) {
        import std.string, std.exception;
        _data = AisMsg5_make (body.toStringz, padding);
        enforce (_data.parse_error == 0,
                 format ("Message parse failed: %s - %s", body, padding));
    }
    ~this() {
        AisMsg5_destroyChildren (&_data);
    }
    this(this) {
        AisMsg5_postblit (&_data);
    }
        
    string toString() {
        import std.format;
        return format("[dlibaiswrap.AisMsg5](%s)", _data);
    }
}

unittest {
    auto msg = AisMsg5("55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::" ~
                       "4A80?4i@E531@0000000000000", 2);
    // {u'destination': u'SEATTLE@@@@@@@@@@@@@', u'dim_d': 10L, u'name': u'MT.MITCHELL@@@@@@@@@', u'eta_hour': 8L, u'ais_version': 0L, u'draught': 6.0, u'mmsi': 369190000L, u'repeat_indicator': 0L, u'dim_b': 90L, u'dim_c': 10L, u'dte': 0L, u'dim_a': 90L, u'eta_day': 2L, u'eta_minute': 0L, u'callsign': u'WDA9674', u'spare': 0L, u'eta_month': 1L, u'type_and_cargo': 99L, u'fix_type': 1L, u'id': 5L, u'imo_num': 6710932L}
    import std.string;
    assert (msg.mmsi == 369190000);
    assert (msg.destination.fromStringz == "SEATTLE");
    assert (msg.shipname.fromStringz == "MT.MITCHELL");
    assert (msg.callsign.fromStringz == "WDA9674");
    assert (msg.shiptype == 99);
    assert (msg.dte == false);
    assert (msg.minute == 0);
    assert (msg.imo == 6710932);
    import std.math;
    assert (msg.draught.approxEqual(6.0));
    assert (msg.to_bow == 90);

    // Test postblit
    auto dupMsg = msg;
    assert (dupMsg.destination.fromStringz == "SEATTLE");
    assert (dupMsg.destination != msg.destination);
    assert (dupMsg.callsign.fromStringz == "WDA9674");
    assert (dupMsg.callsign != msg.callsign);
    assert (dupMsg.shipname.fromStringz == "MT.MITCHELL");
    assert (dupMsg.shipname != msg.shipname);
}
    

//  --------------------------------------------------------------------------
//  AisMsg18

struct AisMsg18 {
    C_AisMsg18 _data;
    alias _data this;

    this(T)(in T body, size_t padding) if(isSomeString!T) {
        import std.string, std.exception;
        _data = AisMsg18_make (body.toStringz, padding);
        enforce (_data.parse_error == 0,
                 format ("Message parse failed: %s - %s", body, padding));
    }
    ~this() {
        AisMsg18_destroyChildren (&_data);
    }
    this(this) {
        AisMsg18_postblit (&_data);
    }

    string toString() {
        import std.format;
        return format("[dlibaiswrap.AisMsg18](%s)", _data);
    }
}

unittest {
    // !AIVDM,1,1,,B,B5MiOp0006g4up6:EV403wr5oP06,0*38
    // {u'true_heading': 511L, u'unit_flag': 1L, u'sog': 0.0, u'spare2': 0L, u'timestamp': 52L, u'mmsi': 366764000L, u'repeat_indicator': 0L, u'mode_flag': 0L, u'm22_flag': 1L, u'raim': True, u'commstate_cs_fill': 393222L, u'commstate_flag': 1L, u'display_flag': 0L, u'spare': 0L, u'dsc_flag': 1L, u'cog': 0.0, u'y': 43.072161666666666, u'x': -70.71106666666667, u'position_accuracy': 0L, u'id': 18L, u'band_flag': 1L}
    auto msg = AisMsg18("B5MiOp0006g4up6:EV403wr5oP06", 0);
    assert (msg.mmsi == 366764000);
    import std.math;
    assert (msg.lat.approxEqual(43.072161666666666));
    assert (msg.lon.approxEqual(-70.71106666666667));
    assert (msg.msg22 == true);
}


//  --------------------------------------------------------------------------
//  AisMsg19

struct AisMsg19 {
    C_AisMsg19 _data;
    alias _data this;

    this(T)(in T body, size_t padding) if(isSomeString!T) {
        import std.string, std.exception;
        _data = AisMsg19_make (body.toStringz, padding);
        enforce (_data.parse_error == 0,
                 format ("Message parse failed: %s - %s", body, padding));
    }
    ~this() {
        AisMsg19_destroyChildren (&_data);
    }
    this(this) {
        AisMsg19_postblit (&_data);
    }

    string toString() {
        import std.format;
        return format("[dlibaiswrap.AisMsg19](%s)", _data);
    }
}

unittest {
    // !AIVDM,1,1,6,A,C5MtL4eP0FK?P@4I96hG`urH@2fF0000000000000000?P000020,0*4D
    // {u'fix_type': 1L, u'type_and_cargo': 31L, u'sog': 0.10000000149011612, u'spare2': 12L, u'repeat_indicator': 0L, u'id': 19L, u'spare3': 0L, u'true_heading': 123L, u'mmsi': 366943250L, u'timestamp': 52L, u'dim_d': 0L, u'assigned_mode': 0L, u'dim_b': 0L, u'raim': False, u'dim_c': 0L, u'spare': 216L, u'dim_a': 0L, u'name': u'HAWK@@@@@@@@@@@@@@@@', u'dte': 0L, u'cog': 37.79999923706055, u'y': 30.708233333333332, u'x': -88.04346666666666, u'position_accuracy': 0L}
    auto msg = AisMsg19("C5MtL4eP0FK?P@4I96hG`urH@2fF0000000000000000?P000020", 0);
    assert (msg.mmsi == 366943250);
    assert (msg.to_bow == 0);
    import std.string;
    assert (msg.shipname.fromStringz == "HAWK");
    import std.math;
    assert (msg.course.approxEqual(37.79999923706055));
    assert (msg.lat.approxEqual(30.708233333333332));

    // Test postblit
    auto dupmsg = msg;
    assert (dupmsg.shipname != msg.shipname);
    assert (dupmsg.shipname.fromStringz() == "HAWK");
}


//  --------------------------------------------------------------------------
//  AisMsg24

struct AisMsg24 {
    private C_AisMsg24 _data;

    auto parse_error() const {return _data.parse_error;}
    auto type()        const {return _data.type;}
    auto repeat()      const {return _data.repeat;}
    auto mmsi()        const {return _data.mmsi;}
    auto partno()      const {return _data.partno;}

    // Part A
    auto shipname() const {enforce(partno == 0); return _data.shipname;}
    // Check used in static reflection
    bool has_shipname() const {return partno == 0;}

    // Part B
    auto shiptype() const {enforce(partno == 1); return _data.shiptype;}
    auto vendorid() const {enforce(partno == 1); return _data.vendorid;}
    auto callsign() const {enforce(partno == 1); return _data.callsign;}
    auto to_bow()   const {enforce(partno == 1); return _data.to_bow;}
    auto to_stern() const {enforce(partno == 1); return _data.to_stern;}
    auto to_port()  const {enforce(partno == 1); return _data.to_port;}
    auto to_starboard() const {enforce(partno == 1); return _data.to_starboard;}
    // Checks used in static reflection
    bool has_shiptype() const {return partno == 1;}
    bool has_vendorid() const {return partno == 1;}
    bool has_callsign() const {return partno == 1;}
    bool has_to_bow()   const {return partno == 1;}
    bool has_to_stern() const {return partno == 1;}
    bool has_to_port()  const {return partno == 1;}
    bool has_to_starboard() const {return partno == 1;}

    this(T)(in T body, size_t padding) if(isSomeString!T) {
        import std.string, std.exception;
        _data = AisMsg24_make (body.toStringz, padding);
        enforce (_data.parse_error == 0,
                 format ("Message parse failed: %s - %s", body, padding));
    }
    ~this() {
        AisMsg24_destroyChildren (&_data);
    }
    this(this) {
        AisMsg24_postblit (&_data);
    }

    string toString() {
        import std.format;
        return format("[dlibaiswrap.AisMsg24](%s)", _data);
    }
}

unittest {
    // Type A
    // !AIVDM,1,1,,B,HE2K5MA`58hTpL0000000000000,2*37
    // {u'mmsi': 338085237L, u'repeat_indicator': 1L, u'id': 24L, u'name': u'ZARLING@@@@@@@@@@@@@', u'part_num': 0L}
    {
        auto msg = AisMsg24("HE2K5MA`58hTpL0000000000000", 2);
        assert (msg.mmsi == 338085237);
        import std.string;
        assert (msg.has_shipname);
        assert (msg.shipname.fromStringz == "ZARLING");
        assert (msg.partno == 0);
        assert (! msg.has_shiptype);
        assert (! msg.has_callsign);

        // postblit
        auto dupmsg = msg;
        assert (dupmsg.shipname != msg.shipname);
        assert (dupmsg.shipname.fromStringz == "ZARLING");        
    }

    // Type B
    // !AIVDM,1,1,,B,H3pro:4q3?=1B0000000000P7220,0*59
    // {'id': 24, 'repeat_indicator': 0, 'mmsi': 261011240, 'part_num': 1, 'type_and_cargo': 57, 'vendor_id': 'COMAR@@', 'callsign': '@@@@@@@', 'dim_a': 4, 'dim_b': 7, 'dim_c': 2, 'dim_d': 2, 'spare': 0}
    {
        auto msg = AisMsg24("H3pro:4q3?=1B0000000000P7220", 0);
        assert (msg.partno == 1);
        assert (msg.mmsi == 261011240);
        assert (msg.has_vendorid);
        import std.string;
        assert (msg.vendorid.fromStringz == "COMAR");
        assert (msg.callsign.fromStringz == "");
        assert (msg.to_starboard == 2);
        assert (msg.shiptype == 57);
        assert (msg.has_shiptype);
        assert (! msg.has_shipname);

        // postblit
        auto dupmsg = msg;
        assert (dupmsg.vendorid != msg.vendorid);
        assert (dupmsg.callsign != msg.callsign);
        assert (dupmsg.vendorid.fromStringz == "COMAR");
        assert (dupmsg.callsign.fromStringz == "");
    }
}


//  --------------------------------------------------------------------------
//  AisMsg27

struct AisMsg27 {
    C_AisMsg27 _data;
    alias _data this;

    this(T)(in T body, size_t padding) if(isSomeString!T) {
        import std.string, std.exception;
        _data = AisMsg27_make (body.toStringz, padding);
        enforce (_data.parse_error == 0,
                 format ("Message parse failed: %s - %s", body, padding));
    }
    ~this() {
        AisMsg27_destroyChildren (&_data);
    }
    this(this) {
        AisMsg27_postblit (&_data);
    }

    string toString() {
        import std.format;
        return format("[dlibaiswrap.AisMsg27](%s)", _data);
    }
}

unittest {
    // !AIVDM,1,1,,A,KrJN9vb@0?wl20RH,0*7A,raishub,1342653118
    // {'id': 27, 'repeat_indicator': 3, 'mmsi': 698845690, 'position_accuracy': 1, 'raim': False, 'nav_status': 9, 'x': 0.105, 'y': -2.5533333333333332, 'sog': 1, 'cog': 38, 'gnss': True, 'spare': 0}
    auto msg = AisMsg27("KrJN9vb@0?wl20RH", 0);
    assert (msg.mmsi == 698845690);
    assert (msg.type == 27);
    import std.math;
    assert (msg.speed.approxEqual (1.0));
    assert (msg.course.approxEqual (38.0));
    assert (msg.gnss == 0);  // NB gnss=0 true NOT false
    assert (msg.repeat == 3);
    assert (msg.lat.approxEqual (-2.5533333333333332));
    assert (msg.lon.approxEqual (0.105));
}

