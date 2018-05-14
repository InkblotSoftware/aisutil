module aisutil.simpleshiptypes;

// Simplified version of the AIS shiptypes schema, plus conversion functions

enum SimpleShiptype {
    NotBroadcast,   // we don't haven an AIS static data message
    
    NotAvailable,  // AIS message says 'not available'
    Invalid,  // AIS spec doesn't allow the number; inc 'reserved [for future use]'
    Other,    // Either AIS 'other' category, or a category that isn't
              // obviously one of the below

    Fishing,
    Utility,
    SailingOrPleasure,
    Passenger,
    Cargo,
    Tanker,
};

// Helper
private bool isBetween (int val, int minClosed, int maxOpen) {
    return minClosed <= val && val < maxOpen; }

// Convert an actual shiptype code to a simple shiptype
SimpleShiptype simplifyShiptype (int shiptype) {
    if (shiptype < 0)
        return SimpleShiptype.Invalid;

    if (shiptype == 0)
        return SimpleShiptype.NotAvailable;

    if (shiptype.isBetween (1, 20))  // 'Reserved'
        return SimpleShiptype.Invalid;

    if (shiptype.isBetween (20, 30))  // 'Wing in ground'
        return SimpleShiptype.Other;

    if (shiptype == 30)
        return SimpleShiptype.Fishing;

    if (shiptype.isBetween (31, 36))
        return SimpleShiptype.Utility;

    if (shiptype.isBetween (36, 37))
        return SimpleShiptype.SailingOrPleasure;

    if (shiptype.isBetween (38, 39))  // Reserved
        return SimpleShiptype.Invalid;

    if (shiptype.isBetween (40, 50))  // 'High speed craft'
        return SimpleShiptype.Other;

    if (shiptype.isBetween (50, 60))
        return SimpleShiptype.Utility;

    if (shiptype.isBetween (60, 70))
        return SimpleShiptype.Passenger;

    if (shiptype.isBetween (70, 80))
        return SimpleShiptype.Cargo;

    if (shiptype.isBetween (80, 90))
        return SimpleShiptype.Tanker;

    if (shiptype.isBetween (90, 100))
        return SimpleShiptype.Other;

    return SimpleShiptype.Invalid;
}
