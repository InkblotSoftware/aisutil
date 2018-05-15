//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.aisnmeagrouping;
import aisutil.daisnmea;
import std.exception, std.algorithm, std.range, std.stdio;

// Multipart message fragment grouper
// ----------------------------------
//
// Groups by raw nmea message data, i.e. uses messageid, fragnum and fragcnt
// from the nmea fields.
//
// Add new messages with pushMsg(), which returns true iff all the messages
// for that sentence have been received. After this you can call popGroup()
// with any nmea fragment from that sentence to get the whole group back,
// clearning it from the grouper.
//
// Submit the message with fragnum 1 first, as this clears the stored frament
// group. Then you can submit subsequent messages for that group in any order
// (though you probably don't want to).
//
// Doesn't handle singlepart sentences; throws if you provide one.
//
// Throws if you submit obviously invalid data e.g. the same message twice,
// so be sure to wrap repeated calls to pushMsg() in a try/catch.
//
// Never expires groups unfinished, but this shouldn't be a problem in practice
// as messageIDs are always small and get reused, hitting the "fragnum 1" logic
// above.

struct AisGrouper_BareNmea {
    @disable this(this);

    bool pushMsg(AisNmeaParser par) {
        auto mid = par.messageid;
        auto fnum = par.fragnum;
        auto fcnt = par.fragcount;
        enforce(fcnt > 1);  // Clients mustn't provide singlepart messages

        // Grow the stored group with the provided message
        if (!(mid in _queuedMsgs) || fnum == 1)
            _queuedMsgs[mid] = [];
        auto curGrp = _queuedMsgs [mid];
        _queuedMsgs [mid] = curGrp ~ par;

        // We always store sorted
        sort!((a,b) => a.fragnum < b.fragnum)(_queuedMsgs[mid]);

        // Clear and bail if the newly-grown group isn't 'valid'
        auto finGroup = _queuedMsgs [mid];
        if (! isValidPartialGroup (finGroup)) {
            _queuedMsgs.remove (mid);
            import std.string;
            enforce (false,
                     format ("AisGrouper_BareNmea: not valid partial group: %s",
                             finGroup));
        }

        return isCompleteGroup(_queuedMsgs[mid]);
    }
        
    AisNmeaParser[] popGroup(in ref AisNmeaParser par) {
        auto res = _queuedMsgs[par.messageid].dup;
        _queuedMsgs.remove(par.messageid);
        return res;
    }

    // Is a group of parsed multipart fragement messages complete?
    private static bool isCompleteGroup(in AisNmeaParser[] group) {
        assert (group.length >= 1);
        auto reqLen = group[0].fragcount;
        assert (group.length <= reqLen);
        return group.length == reqLen;
    }

    // Does the set of messages we have comply with how they're supposed to be?
    private static isValidPartialGroup(in AisNmeaParser[] group) {
        return    group.map!(p => p.fragnum).isSorted()
               // Only one msg for each frag num
               && (group.map!(p => p.fragnum).uniq.array.length == group.length)
               // All have the same message id (sanity check)
               && (group.map!(p => p.messageid).uniq.array.length == 1);
    }
    
    // We group by nmea sequence id
    private alias SeqID = size_t;
    private AisNmeaParser[][SeqID] _queuedMsgs;
}


unittest {
    auto grouper = AisGrouper_BareNmea();
    auto nmea = AisNmeaParser.make();
    bool ok;
    bool finished;

    //  --------------------------------------------------------------------------
    //  Test 'all fine' path
    {
        // Message 1
        ok = nmea.tryParse ("!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh00000000" ~
                            "1S;AJ::4A80?4i@E53,0*3E");
        assert (ok);
        finished = grouper.pushMsg (nmea);
        assert (! finished);

        // Message 2
        ok = nmea.tryParse ("!AIVDM,2,2,3,B,1@0000000000000,2*55");
        assert (ok);
        finished = grouper.pushMsg (nmea);
        assert (finished);

        auto grp = grouper.popGroup (nmea);
        assert (grp.length == 2);
        assert (grp[0].payload == "55P5TL01VIaAL@7WKO@mBplU@<PDhh00000000" ~
                                  "1S;AJ::4A80?4i@E53");
        assert (grp[1].payload == "1@0000000000000");
    }

    //  --------------------------------------------------------------------------
    //  Test restart after adding message 1
    {
        // Message 2
        ok = nmea.tryParse ("!AIVDM,2,2,3,B,1@0000000000000,2*55");
        assert (ok);
        finished = grouper.pushMsg (nmea);
        assert (! finished);

        // Message 1
        ok = nmea.tryParse ("!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh00000000" ~
                            "1S;AJ::4A80?4i@E53,0*3E");
        assert (ok);
        finished = grouper.pushMsg (nmea);
        assert (! finished);

        // Message 2
        ok = nmea.tryParse ("!AIVDM,2,2,3,B,1@0000000000000,2*55");
        assert (ok);
        finished = grouper.pushMsg (nmea);
        assert (finished);

        auto grp = grouper.popGroup (nmea);
        assert (grp.length == 2);
        assert (grp[0].payload == "55P5TL01VIaAL@7WKO@mBplU@<PDhh00000000" ~
                                  "1S;AJ::4A80?4i@E53");
        assert (grp[1].payload == "1@0000000000000");
    }

    //  --------------------------------------------------------------------------
    //  Test adding the same (non-first) message twice throws
    {
        // Message 2
        ok = nmea.tryParse ("!AIVDM,2,2,3,B,1@0000000000000,2*55");
        assert (ok);
        finished = grouper.pushMsg (nmea);
        assert (! finished);

        // Message 2
        ok = nmea.tryParse ("!AIVDM,2,2,3,B,1@0000000000000,2*55");
        assert (ok);
        assertThrown (grouper.pushMsg (nmea));
    }

    //  --------------------------------------------------------------------------
    //  Check throws on singlepart sentences
    {
        ok = nmea.tryParse ("!AIVDM,1,1,,B,H3pro:4q3?=1B0000000000P7220,0*59");
        assert (ok);
        assertThrown (grouper.pushMsg (nmea));
    }
}
