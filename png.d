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

import jpeg;

/**
* Png class.
*/
class Png {

    enum Chunk {
        NONE,
        IHDR,
        IDAT
    }

    /// Construct with a filename, and parse data
    this(string filename) {

        /// Loop through the image data
        auto data = cast(ubyte[]) read(filename);
        foreach (bite; data) {
            if (errorState.code == 0) {
                parse(bite);
            } else {
                debug {
                    writeln("ERROR: ", errorState.message);
                }
                break;
            }
        }
    }


    void parse(ubyte bite) {

        segment.buffer ~= bite;

        if (!haveHeader && (segment.buffer.length == 8)) {
            if (segment.buffer[0..8] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
                /// File has correct header
                segment.buffer.clear;
                pendingChunk = true;
                haveHeader = true;
            } else {
                /// Not a valid png
                errorState.code = 1;
                errorState.message = "Header does not match PNG type!";
                writefln("%(%02x %)", segment.buffer);
                return;
            }
        }

        if (pendingChunk && segment.buffer.length == 8) {

            pendingChunk = false;

            segment.chunkLength = fourBytesToInt(segment.buffer[0..4]);

            char[] type = cast(char[])segment.buffer[4..8];

            if (type == "IHDR") {
                segment.chunkType = Chunk.IHDR;
            } else if (type == "IDAT") {
                segment.chunkType = Chunk.IDAT;
            } else {
                segment.buffer.clear;
                pendingChunk = true;
            }
        }

        if (haveHeader && !pendingChunk && (segment.buffer.length == segment.chunkLength + 4)) {
            processChunk();
            pendingChunk = true;
        }
    }


private:

    bool haveHeader = false;
    bool pendingChunk = false;

    struct PNGSegment {
        Chunk chunkType = Chunk.NONE;
        int chunkLength;
        ubyte[] buffer;
    }
    PNGSegment segment;
    IMGError errorState;


    /// COnvert 4 bytes to an integer
    int fourBytesToInt(ubyte[] bytes) {
        return bytes[0] << 24 | bytes[1] << 16 | bytes[2] <<  8 | bytes[3];
    }


    void processChunk() {

        debug {
            writeln("PNG ProcessChunk: Processing " ~ to!string(segment.chunkType));
        }

        switch(segment.chunkType) {

            /// IHDR chunk contains height, width info
            case(Chunk.IHDR): {

                break;
            }


            default: {
                debug {
                    writeln("PNG ProcessChunk: Un-handled chunk " ~ to!string(segment.chunkType));
                }
                break;
            }
        }


    }



}
