//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.shiplengths;


//  --------------------------------------------------------------------------
//  Ship length category

enum ShipLenCat {
    Invalid,
    NotBroadcast,
    
    Metres0to5,
    Metres5to20,
    MetresAbove20,
}


//  --------------------------------------------------------------------------
//  Finding ship length category from ship length

// Convert ship length in metres to category label
ShipLenCat shipLenCatForLen (double shipLenM) {
    if (shipLenM < 0) {
        return ShipLenCat.Invalid;
    } else
    if (shipLenM.isBetween (0, 5)) {
        return ShipLenCat.Metres0to5;
    } else
    if (shipLenM.isBetween (5, 20)) {
        return ShipLenCat.Metres5to20;
    }
    else {
        return ShipLenCat.MetresAbove20;
    }
}

// Helper
private bool isBetween (double shipLen, double minClosed, double maxOpen) {
    return minClosed <= shipLen && shipLen < maxOpen;
}

unittest {
    assert (shipLenCatForLen(-1) == ShipLenCat.Invalid);
    assert (shipLenCatForLen(0)  == ShipLenCat.Metres0to5);
    assert (shipLenCatForLen(2)  == ShipLenCat.Metres0to5);
    assert (shipLenCatForLen(5)  == ShipLenCat.Metres5to20);
    assert (shipLenCatForLen(6)  == ShipLenCat.Metres5to20);
    assert (shipLenCatForLen(20) == ShipLenCat.MetresAbove20);
    assert (shipLenCatForLen(30) == ShipLenCat.MetresAbove20);
}
