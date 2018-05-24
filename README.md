Easy to use raw AIS processing utilities

This project was created with the kind support of 
[Defra](https://www.gov.uk/government/organisations/department-for-environment-food-rural-affairs)
and [Cefas](https://www.cefas.co.uk/).


Objectives
==========

AISUtil is a set of software tools for working with raw AIS data on
Windows and Linux.

It follows a few main design goals:

- Easy to use by AIS non-experts
- High decode speed
- Trivially easy to deploy (no install needed on Windows)
- Process all the main vessel positional and static data messages
- Be reasonably flexible in what output is generated
- Help the user understand what their data contained

These are all explored at much greater length below.

Note that we now also handle the proprietary AIS variant format used
by the UK's Maritime and Coastguard Authority.


Getting the software
====================

For Windows you can download the main graphical tool from our
[releases page](https://github.com/InkblotSoftware/aisutil/releases).
Just download the binary and double click to run.

Under Linux you'll currently need to build from source, so read
**Building under Linux** below. Basically you install the dependencies
and run `make all`.  It's also possible to distribute Linux binaries,
so get in touch if that seems useful and we can talk about it.

Note that we build and test on 64 bit Windows and Linux; if you need
32 bit support then get in touch.


Introduction to AIS and AIS data
================================

AIS (Automatic Identification System) started life as a safety of life
system, allowing vessels to communicate their position, velocity,
identity, type and other information to each other, avoiding
collisions and generally increasing domain awareness.

Its use is mandated by the IMO for larger and passenger vessels, and
further classes are mandated by other organisations, so it's very
widely used. The systems also retrofit on top of the standard vessel
VHF systems, which helps.

AIS has always been collected by shore-based receivers, both being
displayed in realitime and stored for historical analysis. More
recently satellites have become capable of picking up the signals,
allowing us to track shipping globally, which is quite a
change. Happily market competition is currently driving down prices in
the latter.

The AIS protocol itself is unfortunately horrendous. Interested
readers should examine the closest thing we have to a
[publicly-accessible spec](http://catb.org/gpsd/AIVDM.html)
and those little-prone to depression can read a
[subset of its defects](http://vislab-ccom.unh.edu/~schwehr/papers/toils.txt).
This project attempts to stop the reader having to care.

AIS message types
-----------------

AIS transmitters broadcast a fairly large number of different message
types and subtypes; it's quite a complex world. This software retains
the subset of messages that users genreally want, specifically types
1, 2, 3, 5, 18, 19, 24 and 27, or 'vessel position reports' and
'static data' messages.

From the user's perspective, every ship makes a series of broadcasts
that contain fields you may be interested in. In the JSON outupt any
fields not present in that message don't exist in the output object;
in the CSV output you always get all the columns, but non-broadcast
values get a null in the field.

Static data means fields like ship name, size, static draught etc. -
things that don't change from second to second. Dynamic data is
position, heading, speed over ground, etc. and changing all the
time. The AIS protocol makes the decision to broadcast the latter much
more frequently than the former while the vessel is moving, avoiding
channel saturation. This is especially true as the static data
messages tend to be larger.

Most users will want to consume a message stream as if it consists of
a collection of arbitrary key-value pairs, matching on the contents
each time to see if the data of interest is present to be
extracted. Interested readers can examine the struct definitions in
`source/avmgui/ext/libaiswrap.d` to see exactly what each decoded
message type contains, noting that 1) types 1, 2 and 3 have the same
structure, and 2) type 24 exists in an 'A' form which contains a
shipname, or a 'B' form which contains all the other named fields.

MMSIs - ship broadcast IDs
--------------------------

Every AIS message is tagged with the sender's Maritime Mobile Service
Identity - a non-negative integer which - in theory - uniquely
identifies the sender. The first three decimal digits of the MMSI (the
Maritime Identification Digits or MID) correspond to the country that
issued the MMSI, and thus can be taken as specifying the flag state of
a vessel. A list of MIDs and their meanings can be found
[here](https://en.m.wikipedia.org/wiki/Maritime_identification_digits).
Note that MMSIs not beginning with the digits 2-7 are not officially
issed to ships; for more information see
[here](https://en.m.wikipedia.org/wiki/Maritime_Mobile_Service_Identity).

In general, AIS transmitters can have their MMSI set to any value by
the operator. Further, devices are generally purchased with a standard
value already set, and in practice a number of vessels fail to change
this to their own value, at least for a time. Some equipment like
modern fishing gear also broadcasts on AIS, and generally uses a
standard MMSI for all units. Due to these factors - accidental and
malicious - 'MMSI sharing' is a somewhat common phenomenon, where two
senders create a non-sensical set of information when filtered to that
MMSI. For tracks this manifests as a vessel appearing to 'teleport'
back and forth between two completely unrelated locations every few
seconds.

The standard practice for disambiguating two tracks broadcasting as
one is to define a concept of 'irrational movement' which no physical
vehicle could undertake, typically just an extremely high speed. The
track can be walked by increasing timestamp and split into two tracks
whenever such an irrational movement is encountered; often messages
are annotated with an integer ID specifying the separated track within
that MMSI track. This software will gain this functionality by default
in the very near future.

Ship types
----------

Vessels broadcast a 'ship type' code as part of their static data,
which indicates the vessel's official function. The reliability of
this field varies by domain, with fishing vessels being notably prone
to inaccuracies. It's almost always at least a good starting point,
however.

The vaule transmitted is an integer, with meaning as below. (We're
debating whether to inline these strings into the JSON/CSV data
outputs to avoid users having to keep looking up values, but it will
increase the size quite a bit. Feedback welcome.)

Code | Meaning
--- | ---
0 | Not available
1-19 | Reserved for future use
20 | Wing in ground (WIG), all ships of this type
21 | Wing in ground (WIG), Hazardous category A
22 | Wing in ground (WIG), Hazardous category B
23 | Wing in ground (WIG), Hazardous category C
24 | Wing in ground (WIG), Hazardous category D
25-19 | Wing in ground (WIG), Reserved for future use
30 | Fishing
31 | Towing
32 | Towing: length exceeds 200m or breadth exceeds 25m
33 | Dredging or underwater ops
34 | Diving ops
35 | Military ops
36 | Sailing
37 | Pleasure Craft
38-39 | Reserved
40 | High speed craft (HSC), all ships of this type
41 | High speed craft (HSC), Hazardous category A
42 | High speed craft (HSC), Hazardous category B
43 | High speed craft (HSC), Hazardous category C
44 | High speed craft (HSC), Hazardous category D
45-48 | High speed craft (HSC), Reserved for future use
49 | High speed craft (HSC), No additional information
50 | Pilot Vessel
51 | Search and Rescue vessel
52 | Tug
53 | Port Tender
54 | Anti-pollution equipment
55 | Law Enforcement
56-57 | Spare - Local Vessel
58 | Medical Transport
59 | Noncombatant ship according to RR Resolution No. 18
60 | Passenger, all ships of this type
61 | Passenger, Hazardous category A
62 | Passenger, Hazardous category B
63 | Passenger, Hazardous category C
64 | Passenger, Hazardous category D
65-68 | Passenger, Reserved for future use
69 | Passenger, No additional information
70 | Cargo, all ships of this type
71 | Cargo, Hazardous category A
72 | Cargo, Hazardous category B
73 | Cargo, Hazardous category C
74 | Cargo, Hazardous category D
75-78 | Cargo, Reserved for future use
79 | Cargo, No additional information
80 | Tanker, all ships of this type
81 | Tanker, Hazardous category A
82 | Tanker, Hazardous category B
83 | Tanker, Hazardous category C
84 | Tanker, Hazardous category D
85-88 | Tanker, Reserved for future use
89 | Tanker, No additional information
90 | Other Type, all ships of this type
91 | Other Type, Hazardous category A
92 | Other Type, Hazardous category B
93 | Other Type, Hazardous category C
94 | Other Type, Hazardous category D
95-98 | Other Type, Reserved for future use
99 | Other Type, no additional information

Data correctness
----------------

Similarly to the MMSI data above, almost all transmitted elements in
AIS messages are subject to accidental or deliberate manipulation by
the vessels' operators. This can pose significant challenges to users
of the data.

In practice, however, many fields are generally reliable, and others
are generally quite obvious when wrong: the problems here must
generally be only tackled thouroughly and comprehensively when
building large accurate catalogues; for more specialised and ad hoc
work they can usually be considered and addressed as they appear.

Vessel size data is usually seen as reliable, as it's set by the
engineer on installing the radio and then seldom changed. Positions
are usually obvious when dubious as a discontinuity can be seen as a
vessel applies a translation or similar to its real position; note
that vessels must broadcast correct data when entering ports that
monitor them and require transmission. Timestamps come from the
receiving equipment and are as accurate as you expect your provider to
be (satellite AIS is fine).  Destination string is famously
suspect. Speed over ground and course over ground prove quite reliable
in practice, draught seemingly also (the latter is particularly useful
for gauging tanker fill volume).

TODO discuss a bit more here.


Input data
==========

You need to specity the input format you're working with up front, as
AISutil's programs discard any input data that doesn't parse
correctly, giving you an empty output file when you choose the wrong
one. Happily this is quite obvious, so you just try again with the
other.

NMEA AIS (the normal case)
--------------------------

It's very likely the unprocessed AIS data you have access to will look
like either of these two lines:

```
!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C
\g:1-2-73874,n:157036,s:r003669945,c:1241544035*4A\!AIVDM,1,1,,B,15N4cJ`005Jrek0H@9n`DW5608EP,0*13
```

If you look carefully you'll see they're the same core format, but the
second has a key-value metadata group added to the front, separated by
a '\'.  Satellite AIS companies generally attach such metadata, and
it's the normal source of message timestamps (since AIS messages
helpfully don't carry them).

(If you're interested, you can find a spec for the most commonly used
metadata keys in
[this presentation](http://www.nmea.org/Assets/0183_advancements_nmea_oct_1_2010%20(2).pdf)
(it's technically called a TAG block).
You're likely most interested in 'c', which indicates a Unix epoch
seconds timestamp.)

AISUtil's programs ignore any line that doesn't parse cleanly as
recognised AIS, as it's not unusual to get some other data mixed in
the same file (e.g.  ships can have several pieces of kit dumping data
onto the same bus).  If you get an empty messages output file it's
likely you're providing data in a format the program doesn't
understand.

UK Maritime and Coastguard Authority AIS data
---------------------------------------------

The MCA uses and distributes a variant on the normal NMEA format, and
we read it in AISutil in the same way - just select the "MCA/MMO"
radio box in the GUI or use the `mcaais_to_ndjson` CLI program.

Data in this format is generally composed of lines looking like either
of the following:

```
2013-10-17 00:00:00,306033000,5,54SniJ02>6K10a<J2204l4p@622222222222221?:hD:46b`0>E3lSRCp88888888888880
2016-04-29 00:00:00.000,235104485,H3P=`q@ETD<5@<PE80000000000
```

You can see there's a timestamp, an optional message type (from the
payload), an MMSI (from the payload), and the payload. Multipart
messages are pre-concatenated, so there's no merging to be done, and
one input line corresponds to one output message, assuming no decode
errors.

If you're really interested, `source/aisutil/mcadata.d` contains a
spec for the format we inferred from working with some data
samples. Please do send us updates and improvements if you spot a
mistake.


Ouptut message data formats
===========================

The programs generate either CSV or newline-delimited JSON file
outputs. (An ND-JSON file carries one JSON object per line, and uses
much less memory to process than storing a single JSON array of
objects in the file.)

Since the CSV format names its fields only once in the first row while
the ND-JSON repeats key names each time, the CSV output is noticeably
smaller on disk. However the ND-JSON output compresses very well, and
both are a similar size once e.g. gzipped.

Choosing between the two is entirely user preference.  The main
advantage of the ND-JSON format is that a subset of its lines can be
copied into another file without worrying about the header row, which
can often be a major advantage. When compressed it makes a very good
cold storage format.


Other output files
==================

As well as the messages CSV/NDJSON file(s), the graphical program
writes a number of other files at the same time, to assist the user in
understanding what their output data contains without needing to
investigate the whole set in a subsequent stage (e.g. with R).

Assuming you've set the main output file containing the run summary
text to *OUTPUT.txt*, the program also generates:

- *OUTPUT_MMSIS.csv* - a summary of all the MMSIs seen in the data
  inupt (ignoring any filtering), including first-broadcast instances
  of the key static vessel data fields.
- *OUTPUT_GEOMAP.png* - a world map showing all the positions where
  positional data was broadcast from, and passed the filters.
  Projection is equirectangular, resolution is 3 pixels per degree.


Data filtering and file segregation
===================================

AIS data often poses analysts and researchers problems due to its
volume: >100mm row datasets are quite normal, and multi billion row
datasets are common. This project addresses this by allowing the user
to:

1. Remove unnecessary data, and
2. Separate the output messages into different files, where only
   one or two of these must (ideally) be latter analysed/processed

Note that both of these features can impose a significant processing
speed cost on the AISUtil programs, depending on the amount of memory
available to the running computer. Both features rely on the 'static
data' (identity etc.)  messages transmitted by vessels, but since
these are transmitted relatively infrequently compared with position
report messages, it is common to receive a large number of position
reports before the necessary data required to apply a
filter/segregator and write these messages to disk can be applied.
During this time these messages must be held in memory. In fact, for
many vessels no static data message ever appears in the source data,
meaning that all its position reports must be retained for the whole
lifetime of the processing job.

However, the programs can actually do a lot of work before the above
becomes apparent, so we recommend doing whatever you want and only
thinking about this if it suddenly starts going unexpectedly and
unacceptably slowly.

Note that 'Other' refers to the 'Other' semantic value broadcast by
AIS, e.g. for ship type meaning "I know the type and it's definitely
not one of the official categores I can state". When the broadcast
contains no value or a not meaningful value, we use the term
NotBroadcast.

Specific filters available
--------------------------

Currently you can filter by broadcast vessel length and by broadcast
vessel type.

We're actively looking for more types of filters that people find
useful, so please get in touch if you have code for one or a
recomendation.

Note that this data can be unreliable, paticularly because of user
error or manipulation, or the because of the MMSI sharing described
above. As such you're advised to use these purely as a guide, and
either reconcile with an external dataset or use some kind of
geospatial analysis to as a second and potentially more accurate
source of vessel nature.

###Vessel length

We group these into standard ranges for ease of use; you can pick one.

- 0-5 metres
- 5-20 metres
- >20 metres
- Don't filter

###Vessel type

Again we group into categories:

- Fishing
- Cargo
- Tanker
- Don't filter

Specific file segregations available
------------------------------------

Output messages are split over a set of files according to the chosen
criterion, these files carrying a name that's the main output name
(see above) with '_SEGMENTATIONTYPE' suffixed, where SEMENTATIONTYPE
is chosen from one of the following:

- Vessel category
- Vessel length category
- Timestamp day (one file per broadcast timestamp day)
- Don't filter

Here vessel length categories are the same as in the filters, and
vessel category is taken from the following simplified version of the
AIS set used in AIS:

- NotBroadcast (we don't haven an AIS static data message)
- NotAvailable (AIS message says 'not available')
- Invalid      (AIS spec doesn't allow the broadcast number;
                inc 'reserved [for future use]')
- Other        (either AIS 'other' category, or a category that isn't
                obviously one of the below)
- Fishing
- Utility
- SailingOrPleasure
- Passenger
- Cargo
- Tanker

We're very keen to have feedback to improve both of these lists.


An example of this software in use
==================================

Suppose Alice is investigating oil tanker ballast discharge behaviour,
and decides to track this through changes in vessel draught while the
vessel has not been stationary for a period (i.e. is not in dock). She
wants to create a list of all such events visible on AIS, and also a
plot from it.

Alice buys a month of Satellite AIS data and unpacks the nmea/nm4
files. She runs the AISUtil gui and adds these files to its input
list, accepting its default output file name of AIS_DATA.txt. Knowing
that tanker broadcast shiptypes are generally reliable she filters
only to include vessels broadcasting their type as one of the tanker
categories. Since her standard ad hoc analysis workflow is based on R
she chooses the CSV output, and to keep the working set size low
during the early stages of her analysis she tells the program to split
out message files into one file per day on which each message was
broadcast. Then she kicks off the processing job.

If she wants, Alice can examine the AIS_DATA_MMSIS.csv file written at
the same time, whcih gives first broadcast static data for all the
MMSIs found in the input data set (not just the messages that past the
filters she set).  She might use this, for example, to see whether
vessel length would be a useful criterion for her to filter on, by
looking at the sizes of very large cargo ships.

Alice now implements her algorithm to the following spec: "Find all
pairs of draught-bearing messages from the time-ordered set of
messages from one MMSI, such that the messages express different
draughts, and that there is at least one rate-of-turn bearing message
in the ten minutes before and at least one in the ten after after the
pair with non-zero rate of turn." She implements this by making two
passes over the MMSI's messages, the first to find pairs of messages
with different draughts, and the second to search for non-zero-turn
messages that validate they don't suggest the vessel is docked.

While tweaking her algorithm Alice runs on just the first day's
messages; when complete she scales up to the full output. She can also
now reprocess the set without any filter to see what happens when the
algorithm is applied to all types of shipping.


Building under Linux
====================

This process is slightly complicated to set up, as the proejct is
written as a C++ and a D part combined. It's perfectly possible to
manage the entire build from CMake rather than using DUB to build the
latter, so it's likely we'll end up moving to that structure
eventually.

First install the following packages from your distro's repositories,
or from source / released binaries if they're not available there:

- [libzmq](http://zeromq.org/) (very likely in repos)
- [CZMQ](http://czmq.zeromq.org/) (likely in repos)
- [aisnmea](https://github.com/InkblotSoftware/aisnmea) (not in repos)
- [DMD D compiler](https://dlang.org/download) (unlikely up to date in repos)
  - NB: [Up to date APT repository for Ubuntu](http://d-apt.sourceforge.net/)
- [CMake](https://cmake.org/) (almost certainly in repositories)
- clang++ or g++

Then build the wrapper for `libais`, which is linked in by the second
D compile stage:

```sh
cd libaiswrap
sh lin_setup_cmake.sh
cd lin_build
make
```

Then build the user-facing D binaries; note that we use GNU make as a
front end for DUB, which can only build one configuration at once:

```sh
cd ../../   # back to repo root
make all
```

You'll find `aisutil` and `aisnmea_to_ndjson` created in `bin/`.


Building under Windows
======================

First, install the following compilers etc.:

- Visual Studio 2015 (or the console tools)
- [DMD D compiler](https://dlang.org/download) (includes the DUB package manager)
- [CMake](https://cmake.org/download/)

Then clone this repository. We include the two required Windows C
libraries as static .obj libraries under `win_lib/`

Under the libaiswrap folder, run `win_setup_cmake.bat` to create a
VS2015 project in the `win_build` directory. Open the solution in
VS2015 and perform a release build.

Finally open a VS2015 console and `cd` to the root directory of this
project.  Run `dub build --arch=x86_64 --build=release` to build the
main graphical tool; it'll appear under `bin/` as `aisutil.exe`.


Program design and source code layout
=====================================

AISUtil is separated into a single back end, which carries out the AIS
data procesing, and a set of front ends that interact with the user.

The front ends are found in `app_src/`, where each file carries a
`main()` function and corresponds to a distinct program. The
`dub.json` DUB configuration file in the project root has a
`configuration` entry for each, building each to a binary.

The code for the back end is found in `source/`, and has
`DecProcFinStats executeDecodeProcess(DecodeProcessDef, NotifyCB)` as
its main entry point, stored in the `source/aisutil/decodeprocess.d`
module.  This function encompases the whole data reading,
transformation and writing pipeline, and the exact behaviour it
executes is specified delcaratively by the caller in the
`DecodeProcessDef` struct (files to process, filters, output format,
where to write, etc.).

Note that `executeDecodeProcess()` takes over the thread, so if you
want to retain interactivity make sure to run it on another. We use
per-thread actors and message passing in the included GUI program.

There's quite a lot of flexability in how to write a file, so we use a
traditional vtable interface there to make it easy to add more output
types; we're expecting more and more to be wanted. See
`source/aisutil/filewriting.d` if you're interested. Reading is very
similar, exposing files as ranges of the `AnyAisMsgPossTS` sum type;
here see `source/aisutil/filereading.d` for more details.

We use the excellent **libais** for AIS wire format decoding. Since
the library doesn't prioritise API and ABI compatibility at the C++
level - it exposes a higher level Python interface - we wrap the
library in the `libaiswrap/` project, which imposes a stable C API and
ABI to application code.

TODO say a little more about file layout and how things link together.


Testing
=======

Unit tests are distributed throughout D modules in `source/` in standard
`unittest` blocks, and can be run using `dub test` in the usual way.
`libaiswrap`, our ABI-preserving wrapper for libais, is tested via D from
these unit tests.

We also supply end-to-end integration tests in the `tests/` folder, which
apply the same data transformations in Python code and check the written
output file from the D command line program matches. Unfortunately we haven't
yet been able to convince an AIS data provider to let us distribute some of
their raw data for testing as part of this project, so you'll have to supply
your own if you want to run the tests - details in the README there.


Technology choices
==================

The main application code is written in the D language, which provides
C-level performance and C/C++ integration via the system linker, along
with a unique set of higher level features including peerless
metaprogramming, a large standard library with extensive range-based
features, and optional garbage collection.  Together these
significantly simplify and shrink the code required required to
implement the project.

Reusable libraries are generally implemented in C, as it offers the
simplest and cleanest integrations with other languages; you can find
the current set of Inkblot Software open source libraries on
**github**. Over time we're hoping to move some of the D code across
into C libraries when it's become obvious what's most generally
useful, to allow more and more people to use the functionality from
their own code.


Code reuse
==========

The vast majority of the code making up this software consists of
libraries under `sources/`, and has no dependancy on any of the user
interfaces.  It's ripe for reuse in other projects, especially if
you're writing in D and don't have to write any interfaces. The MPLv2
open source license is effectively permissive as long as you don't
remove source code from the files and use it in your own.

More broadly we have an ambition to convert a lot of this
functionality into portable C libraries, to allow as many projects and
languages to make use of them. We've made some progress - see our
[other repositories](http://github.com/InkblotSoftware) - but please
do let us know if there's a library you really want written away in
its own repository in C. All feedback is helpful.


Ownership and license
=====================

Project code and assets are Copyright (c) 2017 Inkblot Software
Limited.

Licensed under the Mozilla Public License v2.0.

This means you can link this library into your own projects BSD-style,
but you can't remove code from files within this project and use it
within your own files while keeping those files proprietary.


Other projects included
=======================

We statically link the C++ guts of
[libais](https://github.com/schwehr/libais/) as our AIS wire format
decoder, as well as including a reference to its repo in this project
as a git submodule (`libaiswrap/libaiswrap/libais/`).  It's Apache v2
licensed.

We statically link the standard library and runtime from the
[D programming language](https://dlang.org/), which are Boost licensed.

Our GUI framework is (Dlangui)[https://github.com/buggins/dlangui],
again statically linked and Boost licensed. This transitively depends
on the [Derelict suite](https://github.com/DerelictOrg) which is Boost
licensed.

We also link to [CZMQ](http://czmq.zeromq.org/),
[libzmq](http://zeromq.org/) and
[aisnmea](https://github.com/InkblotSoftware/aisnmea). libzmq is
licensed under the LGPL with a static linking exception (thus allowing
non-copyleft static linking), and the others are MPLv2 licensed. All
are linked dynamically under Linux and statically under Windows, the
latter via pre-built binaries in the `win_libs/` folder.

We bundle the source code for two of Adam Ruppe's
[arsd](https://github.com/adamdruppe/arsd) modules, `color.d` and
`png.d`.  These are released under the Boost license.

