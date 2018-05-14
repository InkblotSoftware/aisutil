### Carries out a 'source of truth' decode of nmea data, usign the (slow)
### python interface to libais.
### Assumes libais is system-installed.

import sys, json
import ais


##  --------------------------------------------------------------------------
##  DESIRED COLS TO MAKE (taken from output csv):

##  tagblock_timestamp
##  accuracy
##  assigned
##  callsign
##  course
##  cs
##  day
##  destination
##  display
##  draught
##  dsc
##  dte
##  epfd
##  gnss
##  heading
##  hour
##  imo
##  lat
##  lon
##  minute
##  mmsi
##  month
##  msg22
##  parse_error
##  partno
##  raim
##  repeat
##  second
##  shipname
##  shiptype
##  speed
##  status
##  to_bow
##  to_port
##  to_starboard
##  to_stern
##  turn
##  type
##  vendorid


##  --------------------------------------------------------------------------
##  Which message types should we include in the output?

def msgHasDesiredType (msg):
    mtype = msg["decoded"]["id"]
    return mtype == 1  or mtype == 2  or mtype == 3  or  \
           mtype == 5  or mtype == 18 or mtype == 19 or  \
           mtype == 24 or mtype == 27


##  --------------------------------------------------------------------------
##  Making the output object from the libais-produced (complex) object

def genMsgOutputDict (msg):
    res = {}
    res["parse_error"] = 0
    if ("matches" in msg) and ("time" in msg["matches"][0]):
        res["tagblock_timestamp"] = msg["matches"][0]["time"]
    
    def has (key):
        return key in msg["decoded"]
    
    def push (srcKey, destKey):
        res[destKey] = msg["decoded"][srcKey]
        
    def pushIfHas (srcKey, destKey):
        if has(srcKey): push (srcKey, destKey)

    if has("rot_over_range"):
        res["turn_valid"] = not msg["decoded"]["rot_over_range"]
        
    pushIfHas ("position_accuracy", "accuracy")
    pushIfHas ("mode_flag", "assigned")
    pushIfHas ("callsign", "callsign")
    pushIfHas ("cog", "course")
    pushIfHas ("commstate_flag", "cs")
    pushIfHas ("eta_day", "day")
    pushIfHas ("destination", "destination")
    pushIfHas ("display_flag", "display")
    pushIfHas ("draught", "draught")
    pushIfHas ("dsc_flag", "dsc")
    pushIfHas ("dte", "dte")
    pushIfHas ("fix_type", "epfd")
    pushIfHas ("gnss", "gnss")
    pushIfHas ("true_heading", "heading")
    pushIfHas ("eta_hour", "hour")
    pushIfHas ("imo_num", "imo")
    pushIfHas ("x", "lon")
    pushIfHas ("y", "lat")
    pushIfHas ("eta_minute", "minute")
    pushIfHas ("mmsi", "mmsi")
    pushIfHas ("eta_month", "month")
    pushIfHas ("m22_flag", "msg22")
    pushIfHas ("part_num", "partno")
    pushIfHas ("raim", "raim")
    pushIfHas ("repeat_indicator", "repeat")
    pushIfHas ("timestamp", "second")
    pushIfHas ("name", "shipname")
    pushIfHas ("type_and_cargo", "shiptype")
    pushIfHas ("sog", "speed")
    pushIfHas ("nav_status", "status")
    pushIfHas ("dim_a", "to_bow")
    pushIfHas ("dim_b", "to_stern")
    pushIfHas ("dim_c", "to_port")
    pushIfHas ("dim_d", "to_starboard")
    pushIfHas ("rot", "turn")
    pushIfHas ("id", "type")
    pushIfHas ("vendor_id", "vendorid")

    return res


##  --------------------------------------------------------------------------
##  main()

if __name__ == '__main__':
    count = 0
    
    with ais.open (sys.stdin) as msgStream:
        for msg in msgStream:
            count += 1
            if count % 1000 == 0:
                sys.stderr.write ("-- Done msgs count: %d\n" % (count,))
            
            ## Pass if message failed to decode
            if "decoded" not in msg:
                continue
        
            if msgHasDesiredType (msg):
                genDict = genMsgOutputDict (msg)
                sys.stdout.write (json.dumps (genDict))
                sys.stdout.write ("\n");

