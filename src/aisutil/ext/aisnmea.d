//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

module aisutil.ext.aisnmea;

// Extern declarations for aisnmea library
// 
// NB we've added const attributes on 'self' that the library API doesn't have
// to help the D type system, as we know the library doesn't mutate the value.
//
// Following code copy-pasted from aisnmea.h and modified.

extern (C):

// Class handle (by pointer)
struct aisnmea_t;

// ctr/dtr/dup
aisnmea_t* aisnmea_new (const(char)* nmea);
void aisnmea_destroy (aisnmea_t** self_p);
aisnmea_t* aisnmea_dup (aisnmea_t *self);

// Set from nmea line
int
aisnmea_parse (aisnmea_t* self, const(char)* nmea);


// -- Accessors

const(char)*
aisnmea_tagblockval (const(aisnmea_t)* self, const(char)* key);

//  Sentence identifier, e.g. "!AIVDM"
//  TODO consider stripping the leading '!'; depends on what clients want.
const(char)*
aisnmea_head (const(aisnmea_t)* self);

//  How many fragments in the message sentence containing this one?
size_t
aisnmea_fragcount (const(aisnmea_t)* self);

//  Which fragment number of the whole sentence is this one? (One-based)
size_t
aisnmea_fragnum (const(aisnmea_t)* self);

//  Sequential message ID, for multi-sentence messages.
//  Often (intentionally) missing, in which case we return -1.
int
aisnmea_messageid (const(aisnmea_t)* self);

//  Radio channel message was transmitted on (NB not the same as
//  unit class, this is about frequency).
//  Theoretically only 'A' and 'B' are allowed, but '1' and '2'
//  are seen, which mean the same things.
//  If no channel was present, or the NMEA column held more than one
//  character, set to -1.
char
aisnmea_channel (const(aisnmea_t)* self);

//  Data payload for the message. This is where the AIS meat lies.
//  Pass this to an AIS message decoding library.
const(char)*
aisnmea_payload (const(aisnmea_t)* self);

//  Number of padding bits included at the end of the payload.
//  The AIS decoding library needs to know this number, so it can strip
//  them off.
size_t
aisnmea_fillbits (const(aisnmea_t)* self);

//  Message checksum. Transmitted in hex.
size_t
aisnmea_checksum (const(aisnmea_t)* self);

//  Returns the AIS message type of the message, or -1 if the message
//  doesn't exhibit a valid AIS messgae type.
//  (This is worked out from the first character of the payload.)
int
aisnmea_aismsgtype (const(aisnmea_t)* self);
