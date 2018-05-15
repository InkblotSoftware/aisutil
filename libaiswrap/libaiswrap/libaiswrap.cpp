//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

#include <cassert>

#include "libaiswrap.h"
#include <ais.h>

// UTILS:
// 
// Make a new string, being 'str' minus any set of '@' and ' ' removed from the
// end of the string
string trimRightSpacesAts (const string& str) {
    auto endPos = str.find_last_not_of ("@ ");
    return str.substr(0, endPos+1);
}


// MAIN EXPORTS:

extern "C" {
    

//  --------------------------------------------------------------------------
//  AisMsg1n2n3
    
AisMsg1n2n3
AisMsg1n2n3_make (const char *body, size_t padding) {
    AisMsg1n2n3 res {};

    libais::Ais1_2_3 par {body, padding};
    if (par.had_error()) {
        res.parse_error = -1;
        return res;
    } else {
        res.parse_error = 0;
    }

    res.type = par.message_id;
    
    res.repeat = par.repeat_indicator;
    
    res.mmsi = par.mmsi;
    res.status = par.nav_status;
    
    res.turn = par.rot;
    res.turn_valid = ! par.rot_over_range;
    res.speed = par.sog;

    res.accuracy = par.position_accuracy;

    res.lat = par.position.lat_deg;
    res.lon = par.position.lng_deg;

    res.course = par.cog;
    res.heading = par.true_heading;

    res.second = par.timestamp;

    res.raim = par.raim;

    return res;
}

void
AisMsg1n2n3_destroyChildren (AisMsg1n2n3 *self) {
    // noop - nothing to destroy
}

void
AisMsg1n2n3_postblit (const AisMsg1n2n3 *self) {
    // nop
}
    

//  --------------------------------------------------------------------------
//  AisMsg5

AisMsg5
AisMsg5_make (const char *body, size_t padding) {
    AisMsg5 res {};

    libais::Ais5 par {body, padding};
    if (par.had_error()) {
        res.parse_error = -1;
        return res;
    } else {
        res.parse_error = 0;
    }

    res.type = par.message_id;
    res.repeat = par.repeat_indicator;

    res.mmsi = par.mmsi;
    
    res.imo = par.imo_num;

    res.callsign = strdup ( trimRightSpacesAts(par.callsign).c_str() );
    res.shipname = strdup ( trimRightSpacesAts(par.name).c_str() );

    res.shiptype = par.type_and_cargo;

    res.to_bow = par.dim_a;
    res.to_stern = par.dim_b;
    res.to_port = par.dim_c;
    res.to_starboard = par.dim_d;

    res.epfd = par.fix_type;

    res.month = par.eta_month;
    res.day = par.eta_day;
    res.hour = par.eta_hour;
    res.minute = par.eta_minute;

    res.draught = par.draught;

    res.destination = strdup ( trimRightSpacesAts(par.destination).c_str() );

    res.dte = par.dte;

    return res;
}

void
AisMsg5_destroyChildren (AisMsg5 *self) {
    if (self->callsign) {
        free (self->callsign);
        self->callsign = NULL;
    }
    if (self->shipname) {
        free (self->shipname);
        self->shipname = NULL;
    }
    if (self->destination) {
        free (self->destination);
        self->destination = NULL;
    }
}

void
AisMsg5_postblit (AisMsg5 *self) {
    if (self->callsign)
        self->callsign = strdup (self->callsign);
    if (self->shipname)
        self->shipname = strdup (self->shipname);
    if (self->destination)
        self->destination = strdup (self->destination);
}


//  --------------------------------------------------------------------------
//  AisMsg18

AisMsg18    
AisMsg18_make (const char *body, size_t padding) {
    AisMsg18 res {};

    libais::Ais18 par {body, padding};
    if (par.had_error()) {
        res.parse_error = -1;
        return res;
    } else {
        res.parse_error = 0;
    }

    res.type = par.message_id;
    res.repeat = par.repeat_indicator;

    res.mmsi = par.mmsi;

    res.speed = par.sog;

    res.accuracy = par.position_accuracy;

    res.lat = par.position.lat_deg;
    res.lon = par.position.lng_deg;

    res.course = par.cog;
    res.heading = par.true_heading;

    res.second = par.timestamp;

    res.cs = par.commstate_flag;
    res.display = par.display_flag;
    res.dsc = par.dsc_flag;
    res.msg22 = par.m22_flag;
    res.assigned = par.mode_flag;
    res.raim = par.raim;

    return res;
}

void
AisMsg18_destroyChildren (AisMsg18 *self) {
    // nop
}

void
AisMsg18_postblit (AisMsg18 *self) {
    // nop
}


//  --------------------------------------------------------------------------
//  AisMsg19

AisMsg19    
AisMsg19_make (const char *body, size_t padding) {
    AisMsg19 res {};

    libais::Ais19 par {body, padding};
    if (par.had_error()) {
        res.parse_error = -1;
        return res;
    } else {
        res.parse_error = 0;
    }

    res.type = par.message_id;
    res.repeat = par.repeat_indicator;

    res.mmsi = par.mmsi;

    res.speed = par.sog;

    res.accuracy = par.position_accuracy;

    res.lat = par.position.lat_deg;
    res.lon = par.position.lng_deg;

    res.course = par.cog;
    res.heading = par.true_heading;

    res.second = par.timestamp;

    res.shipname = strdup ( trimRightSpacesAts(par.name).c_str() );
    res.shiptype = par.type_and_cargo;

    res.to_bow = par.dim_a;
    res.to_stern = par.dim_b;
    res.to_port = par.dim_c;
    res.to_starboard = par.dim_d;

    res.epfd = par.fix_type;
    res.raim = par.raim;
    res.dte = par.dte;
    res.assigned = par.assigned_mode;

    return res;
}

void
AisMsg19_destroyChildren (AisMsg19 *self) {
    if (self->shipname) {
        free (self->shipname);
        self->shipname = NULL;
    }
}

void
AisMsg19_postblit (AisMsg19 *self) {
    if (self->shipname)
        self->shipname = strdup (self->shipname);
}


//  --------------------------------------------------------------------------
//  AisMsg24

AisMsg24    
AisMsg24_make (const char *body, size_t padding) {
    AisMsg24 res {};

    libais::Ais24 par {body, padding};
    if (par.had_error()) {
        res.parse_error = -1;
        return res;
    } else {
        res.parse_error = 0;
    }

    // -- Both parts

    res.type = par.message_id;
    res.repeat = par.repeat_indicator;

    res.mmsi = par.mmsi;

    res.partno = par.part_num;

    // -- Behaviour depends on part number
    
    if (res.partno == 0) {
        // Part A
        res.shipname = strdup( trimRightSpacesAts(par.name).c_str() );
        res.vendorid = NULL;
        res.callsign = NULL;
        return res;
        
    } else
    if (res.partno == 1) {
        // Part B
        res.shiptype = par.type_and_cargo;

        res.vendorid = strdup( trimRightSpacesAts(par.vendor_id).c_str() );
        res.callsign = strdup( trimRightSpacesAts(par.callsign).c_str() );
        
        res.to_bow = par.dim_a;
        res.to_stern = par.dim_b;
        res.to_port = par.dim_c;
        res.to_starboard = par.dim_d;

        return res;
    }
    else {
        // Invalid part number
        res.parse_error = -2;
        return res;
    }
}

void
AisMsg24_destroyChildren (AisMsg24 *self) {
    if (self->shipname) {
        free (self->shipname);
        self->shipname = NULL;
    }
    if (self->vendorid) {
        free (self->vendorid);
        self->vendorid = NULL;
    }
    if (self->callsign) {
        free (self->callsign);
        self->callsign = NULL;
    }
}

void
AisMsg24_postblit (AisMsg24 *self) {
    if (self->shipname)
        self->shipname = strdup (self->shipname);
    
    if (self->vendorid)
        self->vendorid = strdup (self->vendorid);
    
    if (self->callsign)
        self->callsign = strdup (self->callsign);
}


//  --------------------------------------------------------------------------
//  AisMsg27

AisMsg27    
AisMsg27_make (const char *body, size_t padding) {
    AisMsg27 res {};

    libais::Ais27 par {body, padding};
    if (par.had_error()) {
        res.parse_error = -1;
        return res;
    } else {
        res.parse_error = 0;
    }

    res.type = par.message_id;
    res.repeat = par.repeat_indicator;

    res.mmsi = par.mmsi;

    res.accuracy = par.position_accuracy;
    res.raim = par.raim;

    res.status = par.nav_status;

    res.lat = par.position.lat_deg;
    res.lon = par.position.lng_deg;

    res.speed = par.sog;
    res.course = par.cog;

    res.gnss = par.gnss ? 0 : 1;

    return res;
}

void
AisMsg27_destroyChildren (AisMsg27 *self) {
    // nop
}

void
AisMsg27_postblit (AisMsg27 *self) {
    // nop
}


    

    










    
}  // extern "C"
