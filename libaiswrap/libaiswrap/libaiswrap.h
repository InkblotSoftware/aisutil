//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

// C header

// TODO normal guard
#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif


//  --------------------------------------------------------------------------
//  Ais msg 1, 2, 3

typedef struct AisMsg1n2n3 {
    int32_t parse_error;  // 0 iff no error raised during message parse

    int32_t type;
    int32_t repeat;
    
    int32_t mmsi;
    int32_t status;

    double turn;
    bool   turn_valid;  // is the data in 'turn' meaningful?
    double speed;

    int32_t accuracy;
    
    double lat;
    double lon;

    double course;
    double heading;

    int32_t second;

    int32_t raim;

    // TODO radio?
} AisMsg1n2n3;

AisMsg1n2n3
AisMsg1n2n3_make (const char *body, size_t padding);

// Essentially a dtr - frees malloc'd children and nulls out ptrs
void
AisMsg1n2n3_destroyChildren (AisMsg1n2n3 *self);

// Run after byte-copying struct to create new copies of any owned data
void
AisMsg1n2n3_postblit (const AisMsg1n2n3 *self);


//  --------------------------------------------------------------------------
//  Ais msg 5

typedef struct AisMsg5 {
    int32_t parse_error;

    int32_t type;
    int32_t repeat;

    int32_t mmsi;

    int32_t imo;
    
    char *callsign;
    char *shipname;

    int32_t shiptype;

    int32_t to_bow;
    int32_t to_stern;
    int32_t to_port;
    int32_t to_starboard;

    int32_t epfd;

    int32_t month;
    int32_t day;
    int32_t hour;
    int32_t minute;

    double draught;

    char *destination;
    
    bool dte;
} AisMsg5;

AisMsg5
AisMsg5_make (const char *body, size_t padding);

void
AisMsg5_destroyChildren (AisMsg5 *self);

void
AisMsg5_postblit (AisMsg5 *self);    
    

//  --------------------------------------------------------------------------
//  AisMsg18

typedef struct AisMsg18 {
    int32_t parse_error;

    int32_t type;
    int32_t repeat;

    int32_t mmsi;

    double speed;
    
    bool accuracy;

    double lon;
    double lat;

    double course;
    double heading;

    int32_t second;
    
    bool cs;  // Carrier Sense unit
    bool display;  // has display (prob not reliable)
    bool dsc;  // has vhf voice radio with dsc capability
    bool msg22;  // unit can accept channel assign by msg22
    bool assigned;
    bool raim;
} AisMsg18;

AisMsg18
AisMsg18_make (const char *body, size_t padding);

void
AisMsg18_destroyChildren (AisMsg18 *self);

void
AisMsg18_postblit (AisMsg18 *self);
    


//  --------------------------------------------------------------------------
//  AisMsg19

typedef struct AisMsg19 {
    int32_t parse_error;

    int32_t type;
    int32_t repeat;

    int32_t mmsi;

    double speed;
    
    bool accuracy;
    
    double lon;
    double lat;

    double course;
    double heading;

    int32_t second;

    char *shipname;
    int32_t shiptype;

    int32_t to_bow;
    int32_t to_stern;
    int32_t to_port;
    int32_t to_starboard;

    int32_t epfd;
    bool raim;
    bool dte;
    int32_t assigned;
} AisMsg19;

AisMsg19
AisMsg19_make (const char *body, size_t padding);

void
AisMsg19_destroyChildren (AisMsg19 *self);

void
AisMsg19_postblit (AisMsg19 *self);




//  --------------------------------------------------------------------------
//  AisMsg24

typedef struct AisMsg24 {
    int32_t parse_error;

    // -- In both parts

    int32_t type;
    int32_t repeat;

    int32_t mmsi;
    
    int32_t partno;  // 0 for part A, 1 for part B

    // -- In part A only

    char *shipname;

    // -- In part B only
    
    int32_t shiptype;

    char *vendorid;

    // Not parsed by libais
    // TODO find out if good reason why not and consider making a PR to include
    /* int32_t model; */
    /* int32_t serial; */

    char *callsign;

    int32_t to_bow;
    int32_t to_stern;
    int32_t to_port;
    int32_t to_starboard;

    // Not parsed by libais
    // TODO find out if good reason why not and consider making a PR to include
    /* int32_t mothership_mmsi; */
} AisMsg24;

AisMsg24
AisMsg24_make (const char *body, size_t padding);

void
AisMsg24_destroyChildren (AisMsg24 *self);

void
AisMsg24_postblit (AisMsg24 *self);




//  --------------------------------------------------------------------------
//  AisMsg27

typedef struct AisMsg27 {
    int32_t parse_error;

    int32_t type;
    int32_t repeat;

    int32_t mmsi;

    bool accuracy;
    int32_t raim;

    int32_t status;

    double lon;
    double lat;

    double speed;
    double course;

    // NB 0 is a current GNSS position, 1 is NOT.
    int32_t gnss;
} AisMsg27;

AisMsg27
AisMsg27_make (const char *body, size_t padding);

void
AisMsg27_destroyChildren (AisMsg27 *self);

void
AisMsg27_postblit (AisMsg27 *self);

    
    
#ifdef __cplusplus
}
#endif
