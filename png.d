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
        IHDR, /// header
        IDAT, /// image
        PLTE /// palette
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
            segment.buffer.clear;

            if (type == "IHDR") {
                segment.chunkType = Chunk.IHDR;
            } else if (type == "IDAT") {
                segment.chunkType = Chunk.IDAT;
            } else if (type == "PLTE") {
                segment.chunkType = Chunk.PLTE;
            } else {
                segment.buffer.clear;
                pendingChunk = true;
            }
        }

        if (haveHeader && !pendingChunk && (segment.buffer.length == segment.chunkLength + 4)) {
            processChunk();
            pendingChunk = true;
            segment.buffer.clear;
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

    int m_width, m_height;
    int m_bitDepth,
        m_colorType,
        m_compression,
        m_filter,
        m_interlace;

    /**
    * Color types are:
    * Color    Allowed    Interpretation
    * Type    Bit Depths
    * 0       1,2,4,8,16  Each pixel is a grayscale sample.
    * 2       8,16        Each pixel is an R,G,B triple.
    * 3       1,2,4,8     Each pixel is a palette index; a PLTE chunk must appear.
    * 4       8,16        Each pixel is a grayscale sample followed by an alpha sample.
    * 6       8,16        Each pixel is an R,G,B triple, followed by an alpha sample.
    */

    /// COnvert 4 bytes to an integer
    int fourBytesToInt(ubyte[] bytes) {
        return (bytes[0] << 24 | bytes[1] << 16 | bytes[2] <<  8 | bytes[3]);
    }


    void processChunk() {

        debug {
            writeln("PNG ProcessChunk: Processing " ~ to!string(segment.chunkType));
        }

        switch(segment.chunkType) {

            /// IHDR chunk contains height, width info
            case(Chunk.IHDR): {
                m_width = fourBytesToInt(segment.buffer[0..4]);
                m_height = fourBytesToInt(segment.buffer[4..8]);
                m_bitDepth = segment.buffer[8];
                m_colorType = segment.buffer[9];
                m_compression = segment.buffer[10];
                m_filter = segment.buffer[11];
                m_interlace = segment.buffer[12];

                debug {
                    writefln("Width: %s\nHeight: %s\nBitDepth: %s\nColorType: %s\n"
                             "Compression: %s\nFilter: %s\nInterlacing: %s", m_width, m_height, m_bitDepth, m_colorType,
                             m_compression, m_filter, m_interlace);
                }
                break;
            }

            case(Chunk.PLTE): {
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
