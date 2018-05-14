module aisutil.geoheatmap;
import arsd.png, arsd.color;
import std.exception;

// Allows the creation of a geo heatmap with individual pixels highlighted,
// plus the writing of this to a png file.
//
// NB make sure to -J include a directory containing the
// "worldMap1080x540_4.png" file when compiling this module.


//  -----------------------------------------------------------------------
//  Statically load assets on disk

// Read map image from disk
private enum ubyte[] worldMap_pngData_1080x540 = 
                         cast(ubyte[]) import("worldMap1080x540_4.png");


//  -----------------------------------------------------------------------
//  Heatmap png generator and file writer

class GeoHeatmap {
    private immutable pixPerDeg = 3;

    private MemoryImage _img;
    
    this() {
        _img = readPng(worldMap_pngData_1080x540).imageFromPng;
        assert (_img.width == 360 * pixPerDeg);
        assert (_img.height == 180 * pixPerDeg);
    }

    // Silently ignores any positions off the map
    void markLatLon(double lat, double lon) {
        import std.math;
        int lat_pix = cast(int) floor(((-lat)+90) * pixPerDeg);
        int lon_pix = cast(int) floor(  (lon+180) * pixPerDeg);
        _img.setPixel(lon_pix, lat_pix, Color(255,255,0));
    }

    void writePng(in string filename) {
        arsd.png.writePng(filename, _img);
    }
}
