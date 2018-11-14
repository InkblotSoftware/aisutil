module aisutil.transits;
import std.variant, std.exception, core.exception, std.stdio;
import aisutil.ais, aisutil.dlibaiswrap;

//  ======================================================================
//  == Vessel transit finding
//  == ======================
//  ==
//  ==  This module Implements a model that translates timestamp-ascending
//  ==  streams of AIS messages into numbered 'transits', each of which
//  ==  represents a movement by a vessel (here an MMSI) between two points
//  ==  at rest.
//  ==  Thus, any MMSI that is not entirely moored, anchored etc for the
//  ==  whole duration of the period will have one or more transits.
//  ==
//  ==
//  == How to use
//  == ----------
//  ==
//  ==  Clients should create an instnace of struct TransitFinder, and feed
//  ==  AIS messages to it via put(). All such messages should be in timestamp
//  ==  ascending order. The return value is variant TransitResult, which
//  ==  may take any of the following values:
//  ==
//  ==    1. TR_InTransit {TransitID}
//  ==    2. TR_AtRest
//  ==    3. TR_BadMessage
//  ==
//  ==  (1) and (2) represent successful use of the TransitFinder, telling
//  ==  you whether the vessel is in transit or at rest at the point the
//  ==  message you provided was transmitted. (3) means you passed a message
//  ==  with earlier timestamp than the last messages successfully processed.
//  ==
//  ==  TransitID's are used to distinguish between successive transits, and
//  ==  model successive integers starting from 1. You probably want to write
//  ==  these out to CSV etc.
//  ==
//  ==  Note that you *must* not supply a message to the TransitFinder that
//  ==  lacks a speed over ground; it will die on an assert if you do.
//  ==  TODO consider whether we should just return (3) in this case; arguably
//  ==  passing in out of order ts messages is as much of a logic error.
//  ==  You also can't use this module for messages without a timestamp.
//  ==
//  ==
//  == Transit finding model specifics
//  == -------------------------------
//  ==
//  ==  We implement the model described in Calder and Schwehr 2009
//  ==  "Traffic Analysis for the Calibration of Risk Assessment Methods":
//  ==  [PDF](https://pdfs.semanticscholar.org/7e2e/1bb3505c34261a2a3c3a08b0b1ad0a48f3d3.pdf)
//  ==
//  ==  Vessel state is modelled as a state machine, allowing the following
//  ==  states:
//  ==
//  ==    1. TS_AtRest
//  ==    2. TS_InTransit
//  ==    3. TS_CheckEnd {stateStartTS}
//  ==
//  ==  The basic idea is that a vessel moves from "at rest" to "in transit"
//  ==  when it travels at 0.5 knots or above, and moves back to "at rest"
//  ==  when it spends at least 5 minutes travelling at less than 0.2 knots.
//  ==  This latter switching back happens via the CheckEnd state, which
//  ==  merely tracks the time for which the vessel has been travelling at
//  ==  less than 0.2 knots. Going above 0.2 knots returns the vessel to
//  ==  the InTransit state.
//  ==
//  ==  The state at the beginning of a track is determined by the first
//  ==  message's speed: 0.5 knots or above is InTransit, lower is AtRest.
//  ==
//  ==  TransitID's start at 1 for each MMSI, and are incremented under the
//  ==  following circumstances:
//  ==
//  ==    1. The vessel moves from being at rest to being in transit
//  ==    2. The time gap from one message to the next is not less than 10
//  ==       minutes.
//  ==       In this case the above 'start of track' rule applies for state.
//  ==
//  ==  The net effect of this numbering scheme is that each coherent period
//  ==  of not being at rest gets its own number, which can be later analysed.
//  ======================================================================


//  ----------------------------------------------------------------------
//  Public ID and state types

// -- ID of one transit

struct TransitID {
    private int _value;
    alias _value this;
    private TransitID next () { return TransitID (value() + 1); }
    int value () { return _value; }
}

// -- Message push return values

private struct TR_InTransit  { TransitID tid; }
private struct TR_AtRest     {}
private struct TR_BadMessage {}

struct TransitResult {
    private alias State = Algebraic!(TR_InTransit, TR_AtRest, TR_BadMessage);
    
    private State _data;
    alias _data this;

    private this(T) (T state) { _data = state; }

    bool isAtRest     () { return _data.peek!TR_AtRest     () !is null; }
    bool isInTransit  () { return _data.peek!TR_InTransit  () !is null; }
    bool isBadMessage () { return _data.peek!TR_BadMessage () !is null; }

    TransitID transitID () {
        assert (isInTransit ());
        return _data.peek!TR_InTransit .tid;
    }
    
    // Factories
    private static TransitResult AtRest () {
        return TransitResult (TR_AtRest ());
    }
    private static TransitResult InTransit (TransitID tid) {
        return TransitResult (TR_InTransit (tid));
    }
    private static TransitResult BadMessage () {
        return TransitResult (TR_BadMessage ());
    }
}


//  ----------------------------------------------------------------------
//  Private utility types

alias Timestamp = int;
alias Knots = double;
alias Mmsi = int;


//  ----------------------------------------------------------------------
//  Internal state machine

private struct TS_AtRest {}
private struct TS_InTransit {}
private struct TS_CheckEnd { Timestamp stateStartTS; }

private struct TransitState {
    private alias State = Algebraic!(TS_AtRest, TS_InTransit, TS_CheckEnd);
    State _data;
    alias _data this;

    private this(T) (T state) { _data = state; }

    bool isAtRest    () { return _data.peek!TS_AtRest    () !is null; }
    bool isInTransit () { return _data.peek!TS_InTransit () !is null; }
    bool isCheckEnd  () { return _data.peek!TS_CheckEnd  () !is null; }

    static TransitState AtRest () {
        return TransitState (TS_AtRest ());
    }
    static TransitState InTransit () {
        return TransitState (TS_InTransit ());
    }
    static TransitState CheckEnd (Timestamp stateStartTS) {
        return TransitState (TS_CheckEnd (stateStartTS));
    }
}


//  ----------------------------------------------------------------------
//  Turning state machine values to pass-to-caller TransitResult values

private TransitResult toTransitResult (TransitState state, TransitID curTid) {
    return state.visit!(
        (TS_AtRest    s) => TransitResult.AtRest (),
        (TS_InTransit s) => TransitResult.InTransit (curTid),
        (TS_CheckEnd  s) => TransitResult.InTransit (curTid),
    );
}


//  ----------------------------------------------------------------------
//  State transmission test helpers - basically a store of constants

private bool shouldShift_transitToCheckEnd (Knots speed) {
    return speed < 0.2;
}

private bool shouldShift_checkEndToTransit (Knots speed) {
    return speed >= 0.2;
}

private bool shouldShift_restToTransit (Knots speed) {
    return speed >= 0.5;
}

private bool shouldShift_checkEndToRest (int checkEndLengthSecs) {
    return checkEndLengthSecs >= 5 * 60;
}

private bool shouldStartAt_inTransit (Knots speed) {
    stdout.flush;
    return speed >= 0.5;
}

private bool timeDelayTooLongForTransit (int seconds) {
    return seconds >= 10 * 60;
}


//  ----------------------------------------------------------------------
//  Core state switching code
//    NB the function calling this MUST ensure that the message has not-lower
//    msgTS than any other than the state finder has seen for this MMSI

private TransitState nextState (TransitState cur,
                                ref AnyAisMsg msg, int msgTS) {
    assert (msg.hasSpeed);

    return cur.visit!(
        (TS_AtRest s) {
            if (shouldShift_restToTransit (msg.speed))
                return TransitState.InTransit ();
            else
                return TransitState.AtRest ();
        },
        (TS_InTransit s) {
            if (shouldShift_transitToCheckEnd (msg.speed))
                return TransitState.CheckEnd (msgTS);
            else
                return TransitState.InTransit ();
        },
        (TS_CheckEnd s) {
            assert (msgTS >= s.stateStartTS);
            
            if (shouldShift_checkEndToTransit (msg.speed))
                return TransitState.InTransit ();
            else
            if (shouldShift_checkEndToRest (msgTS - s.stateStartTS))
                return TransitState.AtRest ();
            else
                return TransitState.CheckEnd (s.stateStartTS);
        }
    );
}

            
//  ----------------------------------------------------------------------
//  Public entry point - the TransitFinder

struct TransitFinder {
    private Timestamp   [Mmsi] _lastMsgTSs;
    private TransitState[Mmsi] _curStates;
    private TransitID   [Mmsi] _curTids;

    // TODO docs (see module intro text)
    // You MUST call this with a speed-bearing message
    TransitResult put (AnyAisMsg msg, Timestamp msgTS) {
        assert (msg.hasSpeed);
        auto mmsi = msg.mmsi;

        // Fail cleanly if the caller provides a too-early message
        if (mmsi in _lastMsgTSs && msgTS < _lastMsgTSs [mmsi])
            return TransitResult.BadMessage ();

        if (mmsi !in _curStates) {
            // First time seen this mmsi

            TransitState state = shouldStartAt_inTransit (msg.speed)
                                     ? TransitState.InTransit ()
                                     : TransitState.AtRest ();
            TransitID tid = state.isAtRest
                                ? TransitID (0)  // will inc on transit start
                                : TransitID (1);
            _curStates  [mmsi] = state;
            _curTids    [mmsi] = tid;
            _lastMsgTSs [mmsi] = msgTS;

            return state.toTransitResult (tid);
            
        } else {
            // Already have state for this mmsi

            // -- Start a new transit if the message delay was too long
            if (timeDelayTooLongForTransit (msgTS - _lastMsgTSs [mmsi])) {
                TransitState state = shouldStartAt_inTransit (msg.speed)
                                         ? TransitState.InTransit ()
                                         : TransitState.AtRest ();
                auto newTid = _curTids[mmsi].next ();
                _curStates  [mmsi] = state;
                _curTids    [mmsi] = newTid;
                _lastMsgTSs [mmsi] = msgTS;

                return state.toTransitResult (newTid);
            }

            // -- Otherwise calculate new state as normal
            
            TransitState oldState = _curStates [mmsi];
            auto newState = oldState.nextState (msg, msgTS);

            // Increment tid if necessary
            TransitID newTid = (oldState.isAtRest && newState.isInTransit)
                                   ? _curTids [mmsi] .next()
                                   : _curTids [mmsi];
            
            _curStates  [mmsi] = newState;
            _curTids    [mmsi] = newTid;
            _lastMsgTSs [mmsi] = msgTS;

            return newState.toTransitResult (newTid);
        }
    }
}

            
//  ----------------------------------------------------------------------
//  Unit tests

unittest {

    //  ------------------------------------------------------------
    //  Test data

    struct Dat {
        int mmsi;
        double speed;
        int timestamp;
    }
    
    int mmsi1 = 111;
    Dat[] mmsi1_track1 = [Dat (mmsi1, 0.1, 1000),  // at rest
                          Dat (mmsi1, 0.1, 1010),
                          Dat (mmsi1, 0.7, 1020),  // in transit, tid=1
                          Dat (mmsi1, 0.8, 1030),
                          Dat (mmsi1, 0.1, 1040),  // check end
                          Dat (mmsi1, 0.1, 1050),
                          Dat (mmsi1, 0.1, 1450),  // at rest
                          Dat (mmsi1, 0.0, 1460),
                          Dat (mmsi1, 0.9, 1470),  // in transit, tid=2
                          Dat (mmsi1, 0.9, 2500)]; // in transit, tid=3


    //  ------------------------------------------------------------
    //  Check reality matches the test data

    // -- Utils

    // Make a (fresh) test message with given speed
    AnyAisMsg makeMsg (int mmsi, double speed) {
        auto msg = AisMsg1n2n3("177KQJ5000G?tO`K>RA1wUbN0TKH", 0);
        msg.mmsi = mmsi;
        msg.speed = speed;
        return AnyAisMsg (msg);
    }
    
    auto finder = TransitFinder ();
    
    auto doPut = delegate TransitResult (Dat dat) {
        auto msg = makeMsg (dat.mmsi, dat.speed);
        return finder.put (msg, dat.timestamp);
    };

    // -- Run tests
    
    TransitResult res;

    res = doPut (mmsi1_track1 [0]);
    assert (res.isAtRest);
    
    res = doPut (mmsi1_track1 [1]);
    assert (res.isAtRest);
    
    res = doPut (mmsi1_track1 [2]);
    assert (res.isInTransit);
    assert (res.transitID.value == 1);

    res = doPut (mmsi1_track1 [3]);
    assert (res.isInTransit);
    assert (res.transitID.value == 1);

    res = doPut (mmsi1_track1 [4]);
    assert (res.isInTransit);
    assert (res.transitID.value == 1);

    res = doPut (mmsi1_track1 [5]);
    assert (res.isInTransit);
    assert (res.transitID == 1);

    res = doPut (mmsi1_track1 [6]);
    assert (res.isAtRest);

    res = doPut (mmsi1_track1 [7]);
    assert (res.isAtRest);

    res = doPut (mmsi1_track1 [8]);
    assert (res.isInTransit);
    assert (res.transitID == 2);

    res = doPut (mmsi1_track1 [9]);
    assert (res.isInTransit);
    assert (res.transitID == 3);
        
    // TODO ideally more tests
}
