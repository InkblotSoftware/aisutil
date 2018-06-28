##  ==========================================================================
##  Copyright (c) 2017-2018 Inkblot Software Limited
##
##  This Source Code Form is subject to the terms of the Mozilla Public
##  License, v. 2.0. If a copy of the MPL was not distributed with this
##  file, You can obtain one at http:##mozilla.org/MPL/2.0/.
##  ==========================================================================

### USAGE:
###     python check_ndjson_files_same.py FILE1 FILE2
###
### Verifies that two named NDJSON files contain the same data, printing
### out any differences found between the files.
###
### Performs a number of type coercions e.g. 1/0 <-> True/False.
### 
### Skips "mmsi_geotrack" key, as the python decoder doesn't create it.
###
### BEWARE strips ' ' and '@' off the right edge of all strings (as this is
### what libaiswrap does).
###
### NB we only go one level deep in the object tree. This is fine for testing
### this project, but in case this program gets used elsewhere, we fail on an
### assert if a value is not a primitive type.

import sys, json


##  --------------------------------------------------------------------------
##  Floating point comparison util

def isclose(a, b, rel_tol=1e-09, abs_tol=0.0):
    return abs(a-b) <= max(rel_tol * max(abs(a), abs(b)), abs_tol)


##  --------------------------------------------------------------------------
##  String trimming utils (we do these in libaiswrap)

def trimAisStr (string):
    return string.rstrip (" @")


##  --------------------------------------------------------------------------
##  Checking whether two read-from-files dicts are the same

def objsAreSame (obj1, obj2):
    assert type(obj1) is dict
    assert type(obj2) is dict

    ### Main key/val checking
    for key in obj1.keys():
        ## Ignore mmsi_geotrack key
        if key == u"mmsi_geotrack":
            continue
        
        if not key in obj2:
            return False

        val1 = obj1 [key]
        val2 = obj2 [key]

        ## Null val
        if val1 is None:
            if val2 is None:
                pass
            else:
                return False

        ## Int val
        elif type(val1) is int:
            if type(val2) is bool:
                if val1 == 0 and val2 == False:
                    pass
                elif val1 == 1 and val2 == True:
                    pass
                else:
                    return False
            elif type(val2) is int:
                if val1 == val2:
                    pass
                else:
                    return False
            elif type(val2) is float:
                if isclose (float(val1), val2):
                    pass
                else:
                    return False
            else:
                return False

        ## Float val
        elif type(val1) is float:
            if type(val2) is float:
                if isclose (val1, val2):
                    pass
                else:
                    return False
            elif type(val2) is int:
                if isclose (val1, float(val2)):
                    pass
                else:
                    return False
            else:
                return False

        ## String val
        elif type(val1) is str:
            if not type(val2) is str:
                return False
            if trimAisStr(val1) != trimAisStr(val2):
                return False

        ## Unicode val
        elif type(val1) is unicode:
            if not type(val2) is unicode:
                return False
            if trimAisStr(val1) != trimAisStr(val2):
                return False

        ## Bool val
        elif type(val1) is bool:
            if type(val2) is bool:
                if not val1 == val2:
                    return False
            elif type(val2) is int:
                if val1 == True and val2 == 1:
                    pass
                elif val1 == False and val2 == 0:
                    pass
                else:
                    return False
            else:
                return False

        ## Other types not handled
        else:
            assert False, "Type not known: %s (%s)" % (val1, type(val1))

    ### There should be no keys just in obj2 (ignoring mmsi_geotrack)
    for key in obj2.keys():
        if key not in obj1 and key != u"mmsi_geotrack":
            return False

    return True


##  --------------------------------------------------------------------------
##  Object set manager

class ObjectSet:
    def __init__ (self, objs):
        self._objs = list(objs)  # we don't mutate the original

    def remove (self, obj):
        """Removes an object from the internal store that satisfies
        'objsAreSame' with 'obj'. Returns the index it was (just then) stored
        at. Throws if no such object exists."""
        for i in range (len(self._objs)):
            if objsAreSame (obj, self._objs[i]):
                del self._objs[i]
                return i
        raise ValueError("No matching object found %s" % (obj,))

    def objects (self):
        return self._objs


##  --------------------------------------------------------------------------
##  Reading an ndjson file to an array of dicts

def readNdjsonFile (filepath):
    with open (filepath) as f:
        return [json.loads(line) for line in f]
    

##  --------------------------------------------------------------------------
##  Printing 'missing message' notes

def printMissingMessage (fileWith, fileWithout, obj):
    print "--------------------"
    print "%s has this object but %s doesn't: %s" %  \
            (fileWith, fileWithout, obj)


##  --------------------------------------------------------------------------
##  Program unit tests

def unittests():
    def assSame(str1, str2):
        assert objsAreSame (json.loads(str1), json.loads(str2))

    assSame ("{}", "{}")
    assSame ("""{"mmsi":1234}""", """{ "mmsi": 1234 }""")
    assSame ("""{"asdf": 1}""", """{"asdf":1.0}""")
    assSame ("""{"asdf": 1.0}""", """{"asdf":1}""")
    assSame ("""{"asdf": 1.0}""", """{"asdf":1.0000000001}""")
    assSame ("""{"accuracy":0,"course":360,"heading":220,"lat":51.947416666666669,"lon":1.29151666666666665,"mmsi":235101651,"parse_error":0,"raim":0,"repeat":0,"second":14,"speed":102.300003051757812,"status":0,"turn":0,"turn_valid":true,"type":1}""",
             """{"status": 0, "repeat": 0, "turn": 0.0, "speed": 102.30000305175781, "mmsi": 235101651, "lon": 1.2915166666666666, "raim": false, "course": 360.0, "second": 14, "type": 1, "lat": 51.94741666666667, "parse_error": 0, "turn_valid": true, "heading": 220, "accuracy": 0}""")
    assSame ("{}", """{"mmsi_geotrack":2}""")
    assSame ("""{"mmsi_geotrack":2}""", "{}")

    
##  --------------------------------------------------------------------------
##  main()

if __name__ == "__main__":
    unittests()
    
    assert len(sys.argv) == 3
    filepath_1 = sys.argv[1]
    filepath_2 = sys.argv[2]

    objs1 = readNdjsonFile (filepath_1)
    objs2 = readNdjsonFile (filepath_2)

    ### 1 minus 2...

    print "### Checking", filepath_1, "has all the objects in", filepath_2
    os1 = ObjectSet (objs1)
    for o in objs2:
        try:
            idx = os1.remove (o)
            ## TODO make use of idx
        except ValueError:
            printMissingMessage (filepath_2, filepath_1, o)
    for o in os1.objects ():
        printMissingMessage (filepath_1, filepath_2, o)

    ### 2 minus 1...

    print
    print
    print "### Checking", filepath_1, "has all the objects in", filepath_2
    os2 = ObjectSet (objs2)
    for o in objs1:
        try:
            idx = os2.remove (o)
            ## TODO make use of idx
        except ValueError:
            printMissingMessage (filepath_1, filepath_2, o)
    for o in os2.objects ():
        printMissingMessage (filepath_2, filepath_1, o)
