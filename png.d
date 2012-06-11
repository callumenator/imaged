// Written in the D programming language.

/++
+ Copyright: Copyright 2012 -
+ License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+ Authors: Callum Anderson
+ Date: June 6, 2012
+/
module png;

import std.string, std.file, std.stdio, std.math,
       std.range, std.algorithm, std.conv, std.zlib, std.bitmanip;

import image;


/**
* Png loader.
*/
class Png : Decoder {

    enum Chunk {
        NONE,
        IHDR, /// header
        IDAT, /// image
        PLTE, /// palette
        IEND /// end of image
    }

    /// Construct with a filename, and parse data
    this(string filename) {

        zliber = new UnCompress();

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

        if (!m_haveHeader && (segment.buffer.length == 8)) {
            if (segment.buffer[0..8] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
                /// File has correct header
                segment.buffer.clear;
                m_pendingChunk = true;
                m_haveHeader = true;
            } else {
                /// Not a valid png
                m_errorState.code = 1;
                m_errorState.message = "Header does not match PNG type!";
                writefln("%(%02x %)", segment.buffer);
                return;
            }
        }

        if (m_pendingChunk && (segment.buffer.length == 8)) {

            m_pendingChunk = false;

            segment.chunkLength = fourBytesToInt(segment.buffer[0..4]);
            char[] type = cast(char[])segment.buffer[4..8];

            writeln(type);

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

        if (m_haveHeader && !m_pendingChunk && (segment.buffer.length == segment.chunkLength + 8 + 4)) {

            processChunk();

            m_previousChunk = segment.chunkType;
            m_pendingChunk = true;
            segment = PNGSegment();
        }

        m_totalBytesParsed ++;
    } /// parse


private:

    bool m_haveHeader = false;
    Chunk m_previousChunk = Chunk.NONE;
    bool m_pendingChunk = false;
    uint m_totalBytesParsed;
    ubyte m_interlacePass = 0;

    int[7] m_pixPerLine;
    int[7] m_scanLines;

    struct InterLace {
        int imageRow;
        int[7] start_row =      [ 0, 0, 4, 0, 2, 0, 1 ];
        int[7] start_col =      [ 0, 4, 0, 2, 0, 1, 0 ];
        int[7] row_increment =  [ 8, 8, 8, 4, 4, 2, 2 ];
        int[7] col_increment =  [ 8, 8, 4, 4, 2, 2, 1 ];
        int[7] block_height =   [ 8, 8, 4, 4, 2, 2, 1 ];
        int[7] block_width =    [ 8, 4, 4, 2, 2, 1, 1 ];
    }
    InterLace m_ilace;


    struct PNGSegment {
        Chunk chunkType = Chunk.NONE;
        int chunkLength;
        ubyte[] buffer;
    }
    PNGSegment segment;

    ubyte[] scanLine1, scanLine2;
    int m_currentScanLine;
    UnCompress zliber;
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
                    case(2): m_nChannels = 3; m_image = new ImageT!(3,8)(m_width, m_height); break; /// rgb
                    case(3): m_nChannels = 1; break; /// palette
                    case(4): m_nChannels = 2; break; /// greyscale + alpha
                    case(6): m_nChannels = 4; m_image = new ImageT!(4,8)(m_width, m_height); break; /// rgba
                    default: break;
                }

                m_stride = m_nChannels*(m_bitDepth/8);
                m_bytesPerScanline = 1 + m_width*m_stride;

                scanLine1 = new ubyte[](m_bytesPerScanline);

                /// Calculate pixels per line and scanlines per pass for interlacing
                foreach(i; 0..m_width) {
                    if (i % 8 == 0) m_pixPerLine[0] ++;
                    if (i % 8 == 4) m_pixPerLine[1] ++;
                    if (i % 8 == 0 ||
                        i % 8 == 4) m_pixPerLine[2] ++;
                    if (i % 8 == 2 ||
                        i % 8 == 6) m_pixPerLine[3] ++;
                    if (i % 8 == 0 ||
                        i % 8 == 2 ||
                        i % 8 == 4 ||
                        i % 8 == 6 ) m_pixPerLine[4] ++;
                    if (i % 8 == 1 ||
                        i % 8 == 3 ||
                        i % 8 == 5 ||
                        i % 8 == 7 ) m_pixPerLine[5] ++;
                }
                m_pixPerLine[6] = m_width;

                foreach(i; 0..m_height) {
                    if (i % 8 == 0) m_scanLines[0] ++;
                    if (i % 8 == 0) m_scanLines[1] ++;
                    if (i % 8 == 4) m_scanLines[2] ++;
                    if (i % 8 == 0 ||
                        i % 8 == 4) m_scanLines[3] ++;
                    if (i % 8 == 2 ||
                        i % 8 == 6 ) m_scanLines[4] ++;
                    if (i % 8 == 0 ||
                        i % 8 == 2 ||
                        i % 8 == 4 ||
                        i % 8 == 6 ) m_scanLines[5] ++;
                    if (i % 8 == 1 ||
                        i % 8 == 3 ||
                        i % 8 == 5 ||
                        i % 8 == 7 ) m_scanLines[6] ++;
                }



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

                uncompressStream(segment.buffer[8..$-4]);
                break;
            }

            /// Palette chunk
            case(Chunk.PLTE): {

                if (!csum_passed) {
                    errorState.code = 1;
                    errorState.message = "PNG: Checksum failed in IPLTE!";
                    return;
                }

                break;
            }

            /// Image end
            case(Chunk.IEND): {

                uncompressStream(scanLine2, true);
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


    /// Uncompress the stream, apply filters, and store image
    void uncompressStream(ubyte[] stream, bool finalize = false) {

        ubyte[] data;
        if (!finalize) {
            data = cast(ubyte[])(zliber.uncompress(cast(void[])stream));
        } else {
            data = cast(ubyte[])(zliber.flush());
        }

        /// Number of bytes in a scanline depends on the interlace pass
        int bytesPerLine = 0;
        int nscanLines = 0;
        if (m_interlace == 1) {
             bytesPerLine = m_pixPerLine[m_interlacePass]*m_stride + 1;
             nscanLines = m_scanLines[m_interlacePass];
        } else {
            bytesPerLine = m_bytesPerScanline;
            nscanLines = m_height;
        }

        int taken = 0, takeLen = 0;
        auto RGBref = m_image.pixels;

        while (taken < data.length) {

            /// Put data into the lower scanline first
            takeLen = bytesPerLine - scanLine2.length;
            if (takeLen > 0 && taken + takeLen <= data.length) {
                scanLine2 ~= data[taken..taken+takeLen];
                taken += takeLen;
            } else if (takeLen > 0) {
                scanLine2 ~= data[taken..$];
                taken += data.length - taken;
            }

            if (scanLine2.length == bytesPerLine) {

                /// Have a full scanline, so filter it...
                filter();

                /// Put it into the image
                if (m_interlace == 0) {
                    int idx = m_currentScanLine*m_image.width*m_stride;
                    RGBref[idx..idx+m_bytesPerScanline-1] = scanLine2[1..$];
                } else {

                    with(m_ilace) {

                        int pass = m_interlacePass;
                        int col = start_col[pass];
                        int scanline_idx = 1;

                        while (col < m_width) {

                            int idx = (col + imageRow*m_width)*m_stride;

                            foreach(py; 0..1){//min(block_height[pass], m_height - imageRow)) {
                            foreach(px; 0..1){//min(block_width[pass], m_width - col)) {
                                int offset = idx + (px * py*m_width)*m_stride;
                                //writeln(offset % m_width, ", ", offset / m_width);
                                //RGBref[offset..offset+m_stride] = scanLine2[scanline_idx..scanline_idx+m_stride];
                            }
                            }

                            //writeln(scanline_idx, ", ", col, ", ", scanLine2.length);

                            RGBref[idx..idx+m_stride] = scanLine2[scanline_idx..scanline_idx+m_stride];
                            scanline_idx += m_stride;
                            col = col + col_increment[pass];
                        }
                    }

                }

                /// Increment scanline counter
                m_currentScanLine ++;

                /// Swap the scanlines
                auto tmp = scanLine1;
                scanLine1 = scanLine2;
                scanLine2 = scanLine1;
                scanLine2.clear;

                if (m_interlace == 1)
                    m_ilace.imageRow += m_ilace.row_increment[m_interlacePass];

                if (m_interlace == 1 && m_currentScanLine == nscanLines) {
                    m_currentScanLine = 0;
                    m_interlacePass ++;

                    if (m_interlacePass == 7) {
                        m_interlacePass = 0;
                        break;
                    } else {
                        scanLine1 = new ubyte[](m_bytesPerScanline);
                        bytesPerLine = m_pixPerLine[m_interlacePass]*m_stride + 1;
                        nscanLines = m_scanLines[m_interlacePass];
                        m_ilace.imageRow = m_ilace.start_row[m_interlacePass];
                    }
                }
            }

        } /// while

    } /// uncompressStream


    /// Apply filters to a scanline
    void filter() {

        int filterType = scanLine2[0];

        switch(filterType) {
            case(0): { /// no filtering, excellent
                break;
            }
            case(1): { /// difference filter, using previous pixel on same scanline
                filter1();
                break;
            }
            case(2): { /// difference filter, using pixel on scanline above, same column
                filter2();
                break;
            }
            case(3): { /// average filter, average of pixel above and pixel to left
                filter3();
                break;
            }
            case(4): { /// Paeth filter
                filter4();
                break;
            }
            default: {
                writeln("PNG: Unhandled filter (" ~ to!string(filterType) ~ ") on scan line "
                        ~ to!string(m_currentScanLine));
                break;
            }
        } /// switch filterType
    }


    /// Apply filter 1 to scanline (difference filter)
    void filter1() {
        //scanLine2[1+m_stride..$] += scanLine2[1..$-m_stride];

        for(int i=m_stride+1; i<scanLine2.length; i+=m_stride) {
            scanLine2[i..i+m_stride] += ( scanLine2[i-m_stride..i] );
        }
    }


    /// Apply filter 2 to scanline (difference filter, using scanline above)
    void filter2() {
        scanLine2[1..$] += scanLine1[1..$];
    }


    /// Apply filter 3 to scanline (average filter)
    void filter3() {

        scanLine2[1..1+m_stride] += cast(ubyte[])(scanLine1[1..1+m_stride] / 2);

        for(int i=m_stride+1; i<scanLine2.length; i+=m_stride) {
            scanLine2[i..i+m_stride] += cast(ubyte[])(( scanLine2[i-m_stride..i] +
                                                        scanLine1[i..i+m_stride] ) / 2);
        }


    }


    /// Apply filter 4 to scanline (Paeth filter)
    void filter4() {

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


        foreach(i; 0..m_stride) {
            scanLine2[i] += paeth(0, scanLine1[i], 0);
        }

        for(int i=m_stride+1; i<scanLine2.length; i+=m_stride) {
            foreach(j; 0..m_stride) {
                scanLine2[i+j] += paeth(scanLine2[i+j-m_stride], scanLine1[i+j], scanLine1[i+j-m_stride]);
            }
        }

    } /// filter4


}
