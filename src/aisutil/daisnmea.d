//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.daisnmea;
import std.exception, std.traits, std.string;
import aisutil.ext.aisnmea;

// Idiomatic D wrapper for aisnmea c class (parses aisnmea lines)
//
// Construct using make(); this calls the aisnmea_t ctr under the hood.
//
// Throws if you try to fetch a tagblock value that isn't present; check
// with has_tagblockval(str).
// 
// Also throws if you try to access values without first carrying out a
// valid message parse.

struct AisNmeaParser {
    private aisnmea_t* _handle;
    private bool _hasVals = false;  // true iff has had value set by valid parse

    @disable this();
    private this(aisnmea_t* han) {
        _handle = han;
        enforce(_handle);
    }
    this(this) {
        import std.stdio;
        auto oldHandle = _handle;
        _handle = aisnmea_dup (_handle);
    }
    ~this() {
        import std.stdio;
        aisnmea_destroy (&_handle);
    }

    // Public ctr
    static AisNmeaParser make() {
        return AisNmeaParser (aisnmea_new(null));
    }

    // Parse a message with this parser.
    // Returns true iff parse succeeded.
    bool tryParse(T)(in T nmea) if(isSomeString!T) {
        import std.string;
        auto rc = aisnmea_parse (_handle, nmea.toStringz);
        if (rc == 0) {
            _hasVals = true;
            return true;
        } else {
            return false;
        }
    }

    // Fetching/querying tagblock values
    bool has_tagblockval(T)(in T key) const if(isSomeString!T) {
        return aisnmea_tagblockval(_handle, key.toStringz) != null;
    }
    const(char)[] tagblockval(T)(in T key) const if(isSomeString!T) {
        const(char)* ptr = aisnmea_tagblockval(_handle, key.toStringz);
        enforce (ptr);
        return ptr.fromStringz;
    }

    // Value accessors. Only call after making a successful parse.
    size_t        fragcount()  const { assert (_hasVals);
                                       return aisnmea_fragcount(_handle); }
    size_t        fragnum()    const { assert (_hasVals);
                                       return aisnmea_fragnum(_handle); }
    int           messageid()  const { assert (_hasVals);
                                       return aisnmea_messageid(_handle); }
    char          channel()    const { assert (_hasVals);
                                       return aisnmea_channel(_handle); }
    const(char)[] payload()    const { assert (_hasVals);
                                       return aisnmea_payload(_handle).fromStringz; }
    size_t        fillbits()   const { assert (_hasVals);
                                       return aisnmea_fillbits(_handle); }
    int           aismsgtype() const { assert (_hasVals);
                                       return aisnmea_aismsgtype(_handle); }

    string toString() const {
        if (!_hasVals)
            return format ("AisNmeaParser(EMPTY){_handle: %s}", _handle);
        return format ("AisNmeaPaser{_handle: %s, fragcount: %s, fragnum: %s, " ~
                       "messageid: %s, payload: %s, fillbits: %s, aismsgtype: %s}",
                       _handle, fragcount, fragnum,
                       messageid, payload, fillbits, aismsgtype);
    }
}

// Was the source line a singlepart message?
bool isSinglepart(in ref AisNmeaParser par) {
    return par.fragcount == 1;
}
bool isMultipart(in ref AisNmeaParser par) {
    return !par.isSinglepart;
}
    
unittest {
    auto par = AisNmeaParser.make();

    // -- no tagblock message
    
    auto ok = par.tryParse("!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C");
    assert(ok);

    assert (1 == par.fragcount);
    assert (1 == par.fragnum);
    assert (0 == par.fillbits);
    assert ("177KQJ5000G?tO`K>RA1wUbN0TKH" == par.payload);

    // -- bad message
    
    ok = par.tryParse("xxxxxxxxxxxxxx");
    assert (!ok);

    // -- tagblock message

    ok = par.tryParse("\\g:1-2-73874,n:157036,s:r003669945,c:1241544035*4A\\" ~
                      "!AIVDM,1,1,,B,15N4cJ`005Jrek0H@9n`DW5608EP,0*13");
    assert (ok);
    assert (par.has_tagblockval("c"));
    assert (par.tagblockval("c") == "1241544035");
    assert (par.payload == "15N4cJ`005Jrek0H@9n`DW5608EP");
}
