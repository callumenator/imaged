// Written in the D programming language.

/++
+ Copyright: Copyright 2012 -
+ License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+ Authors: Callum Anderson
+ Date: June 6, 2012
+/
module imaged.png;

import std.string, std.file, std.stdio, std.math,
       std.range, std.algorithm, std.conv;

/**
* Png class.
*/
class Png {

    /// Construct with a filename, and parse data
    this(string filename) {

        /// Loop through the image data
        auto data = cast(ubyte[]) read(filename);
        foreach (bite; data) {
            parse(bite);
        }
    }


    void parse(ubyte bite) {

        segment.buffer ~= bite;

        if (segment.buffer.length == 8) {
            writefln("%(%02x %)", segment.buffer);
            int a = 1;
        }

    }



private:

    struct Segment {
        bool headerProcessed;
        int headerLength;
        ubyte[] buffer;
    }
    Segment segment;

}
