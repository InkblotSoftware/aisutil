//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.backlog;
import std.variant, std.typecons, std.stdio, std.range, std.algorithm;
import aisutil.dlibaiswrap, aisutil.ais;

// Store for messages we can't output yet
// (usually because we're waiting for a static data message)


//  --------------------------------------------------------------------------
//  The backlog struct itself

struct MmsiBacklog {
    @disable this(this);
    
    private AnyAisMsgPossTS[][int] _messages;  // key is mmsi

    void push (AnyAisMsg msg, Nullable!int possTS) {
        if (msg.mmsi in _messages) {
            auto cur = _messages [msg.mmsi];
            cur ~= AnyAisMsgPossTS (msg, possTS);
            _messages [msg.mmsi] = cur;
        } else {
            _messages[msg.mmsi] = [];
            push (msg, possTS);
        }
    }
    void push(T) (T obj, Nullable!int possTS) if(isAisMsg!T) {
        push (AnyAisMsg(obj), possTS);
    }

    AnyAisMsgPossTS[] popMmsi (int mmsi) {
        AnyAisMsgPossTS[] res = _messages[mmsi];
        _messages.remove (mmsi);
        return res;
    }

    bool contains (int mmsi) {return (mmsi in _messages) != null;}

    // Get range of all mmsis with data stored
    // TODO make it return a range sometime
    int[] mmsis() {return _messages.byKey.array;}
}
    
unittest {
    auto backlog = MmsiBacklog ();
    immutable mmsi_1 = 111;
    immutable mmsi_2 = 222;

    auto msg1 = AisMsg1n2n3 ();
    msg1.mmsi = mmsi_1;
    msg1.lat = 22.2;
    backlog.push (msg1, Nullable!int(678));

    auto msg2 = AisMsg1n2n3 ();
    msg2.mmsi = mmsi_1;
    msg2.lat = 33.3;
    backlog.push (msg2, Nullable!int(789));

    auto msg3 = AisMsg1n2n3 ();
    msg3.mmsi = mmsi_2;
    msg3.lat = 44.4;
    backlog.push (msg3, Nullable!int(899));

    assert (backlog.mmsis.array.sort.array == [mmsi_1, mmsi_2]);
    assert (backlog.contains (mmsi_1));
    assert (backlog.contains (mmsi_2));

    auto gr1 = backlog.popMmsi (mmsi_1);
    assert (gr1.length == 2);
    
    assert (gr1[0].msg.get!AisMsg1n2n3.mmsi == mmsi_1);
    assert (gr1[0].msg.get!AisMsg1n2n3.lat  == 22.2);
    assert (gr1[0].possTS == 678);

    assert (gr1[1].msg.get!AisMsg1n2n3.mmsi == mmsi_1);
    assert (gr1[1].msg.get!AisMsg1n2n3.lat  == 33.3);
    assert (gr1[1].possTS == 789);

    auto gr2 = backlog.popMmsi (mmsi_2);
    assert (gr2.length == 1);

    assert (gr2[0].msg.get!AisMsg1n2n3.mmsi == mmsi_2);
    assert (gr2[0].msg.get!AisMsg1n2n3.lat  == 44.4);
    assert (gr2[0].possTS == 899);

    assert (! backlog.contains (mmsi_1));
    assert (! backlog.contains (mmsi_2));
    assert (backlog.mmsis.empty);
}
