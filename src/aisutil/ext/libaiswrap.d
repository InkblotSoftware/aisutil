//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.ext.libaiswrap;

// Extern declarations for the libaiswrap library.
// 
// Basically all copy-pasted from libaiswrap.h, with some very
// minor modifications (mostly moving the '*' in pointer types
// one character to the left)

extern (C):

//  --------------------------------------------------------------------------
//  AisMsg1n2n3

alias C_AisMsg1n2n3 = AisMsg1n2n3;
private struct AisMsg1n2n3 {
    int parse_error;

    int type;
    int repeat;

    int mmsi;
    int status;

    double turn;
    bool   turn_valid;
    double speed;

    int accuracy;

    double lat;
    double lon;

    double course;
    double heading;

    int second;

    int raim;

    // TODO radio?
}

AisMsg1n2n3
AisMsg1n2n3_make (const(char)* body, size_t padding);

void
AisMsg1n2n3_destroyChildren (AisMsg1n2n3* self);

void
AisMsg1n2n3_postblit (AisMsg1n2n3* self);


//  --------------------------------------------------------------------------
//  AisMsg5

alias C_AisMsg5 = AisMsg5;
private struct AisMsg5 {
    int parse_error;

    int type;
    int repeat;

    int mmsi;

    int imo;
    
    char* callsign;
    char* shipname;

    int shiptype;

    int to_bow;
    int to_stern;
    int to_port;
    int to_starboard;

    int epfd;

    int month;
    int day;
    int hour;
    int minute;

    double draught;

    char* destination;

    bool dte;
}

AisMsg5
AisMsg5_make (const(char)* body, size_t padding);

void
AisMsg5_destroyChildren (AisMsg5* self);

void
AisMsg5_postblit (AisMsg5* self);


//  --------------------------------------------------------------------------
//  AisMsg18

alias C_AisMsg18 = AisMsg18;
private struct AisMsg18 {
    int parse_error;

    int type;
    int repeat;

    int mmsi;

    double speed;
    
    bool accuracy;

    double lon;
    double lat;

    double course;
    double heading;

    int second;
    
    bool cs;  // Carrier Sense unit
    bool display;  // has display (prob not reliable)
    bool dsc;  // has vhf voice radio with dsc capability
    bool msg22;  // unit can accept channel assign by msg22
    bool assigned;
    bool raim;
}

AisMsg18
AisMsg18_make (const(char)* body, size_t padding);

void
AisMsg18_destroyChildren (AisMsg18* self);

void
AisMsg18_postblit (AisMsg18* self);


//  --------------------------------------------------------------------------
//  AisMsg19

alias C_AisMsg19 = AisMsg19;
private struct AisMsg19 {
    int parse_error;

    int type;
    int repeat;

    int mmsi;

    double speed;
    
    bool accuracy;
    
    double lon;
    double lat;

    double course;
    double heading;

    int second;

    char *shipname;
    int shiptype;

    int to_bow;
    int to_stern;
    int to_port;
    int to_starboard;

    int epfd;
    bool raim;
    bool dte;
    int assigned;
}

AisMsg19
AisMsg19_make (const(char)* body, size_t padding);

void
AisMsg19_destroyChildren (AisMsg19* self);

void
AisMsg19_postblit (AisMsg19* self);


//  --------------------------------------------------------------------------
//  AisMsg24

alias C_AisMsg24 = AisMsg24;
private struct AisMsg24 {
    int parse_error;

    // -- In both parts

    int type;
    int repeat;

    int mmsi;
    
    int partno;  // 0 for part A, 1 for part B

    // -- In part A only

    char* shipname;

    // -- In part B only
    
    int shiptype;

    char* vendorid;

    // Not parsed by libais
    // TODO find out if good reason why not and consider making a PR to include
    /* int model; */
    /* int serial; */

    char* callsign;

    int to_bow;
    int to_stern;
    int to_port;
    int to_starboard;

    // Not parsed by libais
    // TODO find out if good reason why not and consider making a PR to include
    /* int mothership_mmsi; */
}

AisMsg24
AisMsg24_make (const(char)* body, size_t padding);

void
AisMsg24_destroyChildren (AisMsg24* self);

void
AisMsg24_postblit (AisMsg24* self);


//  --------------------------------------------------------------------------
//  AisMsg27

alias C_AisMsg27 = AisMsg27;
private struct AisMsg27 {
    int parse_error;

    int type;
    int repeat;

    int mmsi;

    bool accuracy;
    int raim;

    int status;

    double lon;
    double lat;

    double speed;
    double course;

    int gnss;
}

AisMsg27
AisMsg27_make (const(char)* body, size_t padding);

void
AisMsg27_destroyChildren (AisMsg27* self);

void
AisMsg27_postblit (AisMsg27* self);
    
