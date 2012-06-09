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
import image;

/**
* Png loader.
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
        m_nChannels,
        m_stride;

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

                m_stride = m_nChannels*(m_bitDepth/8);

                debug {
                    writefln("Width: %s\nHeight: %s\nBitDepth: %s\nColorType: %s\n"
                             "Compression: %s\nFilter: %s\nInterlacing: %s\nStride: %s",
                             m_width, m_height, m_bitDepth, m_colorType,
                             m_compression, m_filter, m_interlace, m_stride);
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

        RGB = new ImageT!(3,ubyte)(m_width, m_height);

        foreach(line; 0..m_height) {

            /// Filters can change between scan lines
            ubyte filter = data[getPixelIndex(0, line)-1];

            switch(filter) {
                case(0): { /// no filtering, excellent
                    filter0(line, data);
                    break;
                }

                case(1): { /// difference filter, using previous pixel on same scanline
                    filter1(line, data);
                    break;
                }

                case(2): { /// difference filter, using pixel on scanline above, same column
                    filter2(line, data);
                    break;
                }

                case(3): { /// average filter, average of pixel above and pixel to left
                    filter3(line, data);
                    break;
                }

                case(4): { /// Paeth filter
                    filter4(line, data);
                    break;
                }

                default: {
                    writeln("PNG: Unhandled filter (" ~ to!string(filter) ~ ") on scan line "
                            ~ to!string(line));
                    break;
                }
            }
        }
    } /// uncompressStream


    /// Return the 1D offset for a given pixel at x, y
    uint getPixelIndex(int x, int y) {

        if (x < 0) x = 0;
        if (y < 0) y = 0;

        /// Remeber that each 'row'/scanline starts with 1 byte, for the filter type
        return x*m_nChannels*(m_bitDepth/8) + y*m_width*m_nChannels*(m_bitDepth/8) + (y+1);
    }


    /// Apply filter 0 to scanline (no filter)
    void filter0(uint y, ubyte[] data) {
        uint x;
        foreach(col; 0..m_width) {
            x = getPixelIndex(col,y);
            RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
        }
    }

    /// Apply filter 1 to scanline (difference filter)
    void filter1(uint y, ubyte[] data) {

        uint x = getPixelIndex(0,y);
        RGB.setPixel(0, y, Pixel(data[x], data[x + 1], data[x + 2], 0));

        foreach(col; 1..m_width) {
            x = getPixelIndex(col,y);
            data[x..x+m_stride] += data[x-m_stride..x];
            RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
        }
    }

    /// Apply filter 2 to scanline (difference filter, using scanline above)
    void filter2(uint y, ubyte[] data) {

        if (y == 0) {

            foreach(col; 0..m_width) {
                uint x = getPixelIndex(col,y);
                RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
            }

        } else {

            uint x, b = 0;
            foreach(col; 0..m_width) {
                x = getPixelIndex(col,y);
                b = getPixelIndex(col,y-1);
                data[x..x+m_stride] += data[b..b+m_stride];
                RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
            }
        }
    }

    /// Apply filter 3 to scanline (average filter)
    void filter3(uint y, ubyte[] data) {

        if (y == 0) {

            /// Do the first col
            uint x = getPixelIndex(0,y);
            RGB.setPixel(0, y, Pixel(data[x], data[x + 1], data[x + 2], 0));

            foreach(col; 1..m_width) {
                x = getPixelIndex(col,y);
                data[x..x+m_stride] += cast(ubyte[])(data[x-m_stride..x] / 2);
                RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
            }

        } else {

            /// Do the first col
            uint x = getPixelIndex(0,y);
            uint b = getPixelIndex(0,y-1);
            data[x..x+m_stride] += cast(ubyte[]) (data[b..b+m_stride] / 2);
            RGB.setPixel(0, y, Pixel(data[x], data[x + 1], data[x + 2], 0));

            foreach(col; 1..m_width) {
                x = getPixelIndex(col,y);
                b = getPixelIndex(col,y-1);
                data[x..x+m_stride] += cast(ubyte[])((data[x-m_stride..x] + data[b..b+m_stride])/2);
                RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
            }
        }
    }

    /// Apply filter 4 to scanline (Paeth filter)
    void filter4(uint y, ubyte[] data) {

        int paeth(ubyte a, ubyte b, ubyte c) {
            int p = (a + b - c);
            int pa = abs(p - a);
            int pb = abs(p - b);
            int pc = abs(p - c);

            int pred = 0;
            if ((pa <= pb) && (pa <= pc)) {
                pred = a;
            } else if (pb <= pc) {
                pred = b;
            } else {
                pred = c;
            }
            return pred;
        }

        if (y == 0) {

            /// Do the first col
            uint x = getPixelIndex(0,y);
            RGB.setPixel(0, y, Pixel(data[x], data[x + 1], data[x + 2], 0));

            foreach(col; 1..m_width) {
                x = getPixelIndex(col,y);
                data[x] += paeth(data[x-m_stride], 0, 0);
                data[x + 1] += paeth(data[x+1-m_stride], 0, 0);
                data[x + 2] += paeth(data[x+2-m_stride], 0, 0);
                RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
            }

        } else {

            /// Do the first col
            uint x = getPixelIndex(0,y);
            uint b = getPixelIndex(0,y-1);
            data[x] += paeth(0, data[b], 0);
            data[x + 1] += paeth(0, data[b + 1], 0);
            data[x + 2] += paeth(0, data[b + 2], 0);
            RGB.setPixel(0, y, Pixel(data[x], data[x + 1], data[x + 2], 0));

            foreach(col; 1..m_width) {
                x = getPixelIndex(col,y);
                b = getPixelIndex(col,y-1);
                data[x] += paeth(data[x-m_stride], data[b], data[b-m_stride]);
                data[x + 1] += paeth(data[x+1-m_stride], data[b+1], data[b+1-m_stride]);
                data[x + 2] += paeth(data[x+2-m_stride], data[b+2], data[b+2-m_stride]);
                RGB.setPixel(col, y, Pixel(data[x], data[x + 1], data[x + 2], 0));
            }
        }




    }


}
