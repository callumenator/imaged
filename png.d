// Written in the D programming language.

/++
+ Copyright: Copyright 2012 -
+ License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+ Authors: Callum Anderson
+ Date: June 6, 2012
+/
module imaged.png;

import std.string, std.file, std.stdio, std.math,
       std.range, std.algorithm, std.conv, std.zlib, std.bitmanip;

import jpeg;

/**
* Png class.
*/
class Png {

    enum Chunk {
        NONE,
        IHDR, /// header
        IDAT, /// image
        PLTE, /// palette
        IEND /// end of image
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

        if (pendingChunk && (segment.buffer.length == 8)) {

            pendingChunk = false;

            segment.chunkLength = fourBytesToInt(segment.buffer[0..4]);
            char[] type = cast(char[])segment.buffer[4..8];

            if (type == "IHDR") {
                segment.chunkType = Chunk.IHDR;
            } else if (type == "IDAT") {
                segment.chunkType = Chunk.IDAT;
            } else if (type == "PLTE") {
                segment.chunkType = Chunk.PLTE;
            } else if (type == "IEND") {
                segment.chunkType = Chunk.IEND;
            } else {

            }
        }

        if (haveHeader && !pendingChunk && (segment.buffer.length == segment.chunkLength + 8 + 4)) {

            processChunk();

            /// If this chunk is not an IDAT, and the previous one was, then decode the stored stream
            if (segment.chunkType != Chunk.IDAT && previousChunk == Chunk.IDAT) {
                uncompressStream();
            }

            previousChunk = segment.chunkType;
            pendingChunk = true;
            segment = PNGSegment();
        }



    }

    Image RGB;

private:

    bool haveHeader = false;
    Chunk previousChunk = Chunk.NONE;
    bool pendingChunk = false;

    struct PNGSegment {
        Chunk chunkType = Chunk.NONE;
        int chunkLength;
        ubyte[] buffer;
    }
    PNGSegment segment;
    IMGError errorState;

    ubyte[] zlib_stream;
    uint checkSum;

    int m_width, m_height;
    int m_bitDepth,
        m_colorType,
        m_compression,
        m_filter,
        m_interlace,
        m_bytesPerScanline,
        m_nChannels;

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

        /**
        * Remeber - first 8 bytes in the segment.buffer are length (4byte) and type (4byte)
        * So chunk data begins at index 8 of the buffer. We keep this stuff for calculating
        * the checksum (it actually only uses the chunk data and the type field).
        */

        debug {
            writeln("PNG ProcessChunk: Processing " ~ to!string(segment.chunkType));
        }

        /// Compare checksums, but let chunk types determine how to handle failed checks
        bool csum_passed = true;
        uint csum_calc = crc32(0, segment.buffer[4..$-4]);
        uint csum_read = fourBytesToInt(segment.buffer[$-4..$]);
        if (csum_calc != csum_read)
            csum_passed = false;

        switch(segment.chunkType) {

            /// IHDR chunk contains height, width info
            case(Chunk.IHDR): {

                if (!csum_passed) {
                    errorState.code = 1;
                    errorState.message = "PNG: Checksum failed in IHDR!";
                    return;
                }

                m_width = fourBytesToInt(segment.buffer[8..12]);
                m_height = fourBytesToInt(segment.buffer[12..16]);
                m_bitDepth = segment.buffer[16];
                m_colorType = segment.buffer[17];
                m_compression = segment.buffer[18];
                m_filter = segment.buffer[19];
                m_interlace = segment.buffer[20];

                switch (m_colorType) {
                    case(0): m_nChannels = 1; break; /// greyscale
                    case(2): m_nChannels = 3; break; /// rgb
                    case(3): m_nChannels = 1; break; /// palette
                    case(4): m_nChannels = 2; break; /// greyscale + alpha
                    case(6): m_nChannels = 4; break; /// rgba
                    default: break;
                }

                debug {
                    writefln("Width: %s\nHeight: %s\nBitDepth: %s\nColorType: %s\n"
                             "Compression: %s\nFilter: %s\nInterlacing: %s", m_width, m_height, m_bitDepth, m_colorType,
                             m_compression, m_filter, m_interlace);
                }
                break;
            }

            /// Actual image data
            case(Chunk.IDAT): {

                if (!csum_passed) {
                    errorState.code = 1;
                    errorState.message = "PNG: Checksum failed in IDAT!";
                    return;
                }

                zlib_stream ~= segment.buffer[8..$-4];
                break;
            }

            case(Chunk.PLTE): {

                if (!csum_passed) {
                    errorState.code = 1;
                    errorState.message = "PNG: Checksum failed in IPLTE!";
                    return;
                }

                break;
            }


            default: {
                debug {
                    writeln("PNG ProcessChunk: Un-handled chunk " ~ to!string(segment.chunkType));
                }
                break;
            }
        }
    } /// processChunk


    void uncompressStream() {

        ubyte[] data = cast(ubyte[])(uncompress(cast(void[])zlib_stream));

        RGB = Image(m_width, m_height, Image.Format.R8G8B8);

        uint stride = m_nChannels*(m_bitDepth/8);

        uint offset = 0;
        foreach(line; 0..m_height) {

            /// Filters can change between scan lines
            ubyte filter = data[offset];
            offset ++;

            switch(filter) {
                case(0): { /// no filtering, excellent
                    foreach(col; 0..m_width) {
                        RGB[col, line] = Image.Pixel(swapEndian(data[offset]),
                                                     swapEndian(data[offset + 1]),
                                                     swapEndian(data[offset + 2]));
                        offset += stride;
                    }
                    break;
                }

                case(1): { /// no filtering, excellent

                    RGB[0, line] = Image.Pixel(cast(ubyte)(data[offset]),
                                               cast(ubyte)(data[offset + 1]),
                                               cast(ubyte)(data[offset + 2]));
                    offset += stride;

                    foreach(col; 1..m_width) {
                        RGB[col, line] = Image.Pixel(cast(ubyte)(data[offset] + data[offset - stride]),
                                                     cast(ubyte)(data[offset + 1] + data[offset + 1 - stride]),
                                                     cast(ubyte)(data[offset + 2] + data[offset + 2 - stride]));
                        offset += stride;
                    }
                    break;
                }

                default: {
                    foreach(col; 0..m_width) {
                        offset += stride;
                    }
                    writeln("PNG: Unhandled filter (" ~ to!string(filter) ~ ") on scan line "
                            ~ to!string(line));
                    break;
                }
            }
        }
    }

}
