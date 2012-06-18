// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Date: June 6, 2012
*/
module png;

import std.file,
       std.stdio,
       std.math,
       std.algorithm,
       std.conv,
       std.zlib,
       std.stream;

import image;


/**
* Png decoder.
*/
class PngDecoder : Decoder
{
    enum Chunk
    {
        NONE,
        IHDR, // header
        IDAT, // image
        PLTE, // palette
        IEND // end of image
    }


    // Empty constructor, usefule for parsing a stream manually
    this(in bool logging = false)
    {
        m_logging = logging;
        zliber = new UnCompress();
    }


    // Constructor taking a filename
    this(in string filename, in bool logging = false)
    {
        this(logging);
        parseFile(filename);

    } // c'tor


    // Parse one byte
    void parseByte(ubyte bite)
    {
        segment.buffer ~= bite;

        if (!m_haveHeader && (segment.buffer.length == 8))
        {
            if (segment.buffer[0..8] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            {
                // File has correct header
                segment.buffer.clear;
                m_pendingChunk = true;
                m_haveHeader = true;
            }
            else
            {
                // Not a valid png
                m_errorState.code = 1;
                m_errorState.message = "Header does not match PNG type!";
                return;
            }
        }

        if (m_pendingChunk && (segment.buffer.length == 8))
        {
            m_pendingChunk = false;

            segment.chunkLength = fourBytesToInt(segment.buffer[0..4]);
            char[] type = cast(char[])segment.buffer[4..8];

            if (type == "IHDR")
            {
                segment.chunkType = Chunk.IHDR;
            }
            else if (type == "IDAT")
            {
                segment.chunkType = Chunk.IDAT;
            }
            else if (type == "PLTE")
            {
                segment.chunkType = Chunk.PLTE;
            }
            else if (type == "IEND")
            {
                segment.chunkType = Chunk.IEND;
            }
        }

        if (segment.chunkType != Chunk.IDAT)
        {
            if (m_haveHeader && !m_pendingChunk && (segment.buffer.length == segment.chunkLength + 8 + 4))
            {
                processChunk();
                m_previousChunk = segment.chunkType;
                m_pendingChunk = true;
                segment = PNGSegment();
            }
        }
        else
        {
            if (segment.buffer.length > 8 && segment.buffer.length <= segment.chunkLength + 8)
            {
                uncompressStream([bite]);
            }
            else if (segment.buffer.length == segment.chunkLength + 8 + 4)
            {
                processChunk();
                m_previousChunk = segment.chunkType;
                m_pendingChunk = true;
                segment = PNGSegment();
            }
        }

        m_totalBytesParsed ++;
    } // parseByte


private:

    bool m_haveHeader = false;
    Chunk m_previousChunk = Chunk.NONE;
    bool m_pendingChunk = false;
    uint m_totalBytesParsed;
    ubyte m_interlacePass = 0;

    int[7] m_pixPerLine;
    int[7] m_scanLines;

    struct InterLace
    {
        int imageRow;
        int[7] start_row =      [ 0, 0, 4, 0, 2, 0, 1 ];
        int[7] start_col =      [ 0, 4, 0, 2, 0, 1, 0 ];
        int[7] row_increment =  [ 8, 8, 8, 4, 4, 2, 2 ];
        int[7] col_increment =  [ 8, 8, 4, 4, 2, 2, 1 ];
        int[7] block_height =   [ 8, 8, 4, 4, 2, 2, 1 ];
        int[7] block_width =    [ 8, 4, 4, 2, 2, 1, 1 ];
    }
    InterLace m_ilace;


    struct PNGSegment
    {
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
        m_stride,
        m_pixelScale;

    ubyte[] m_palette;

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

    // COnvert 4 bytes to an integer
    int fourBytesToInt(ubyte[] bytes)
    {
        return (bytes[0] << 24 | bytes[1] << 16 | bytes[2] <<  8 | bytes[3]);
    }


    void processChunk()
    {
        /**
        * Remeber - first 8 bytes in the segment.buffer are length (4byte) and type (4byte)
        * So chunk data begins at index 8 of the buffer. We keep this stuff for calculating
        * the checksum (it actually only uses the chunk data and the type field).
        */

        debug
        {
            if (m_logging) writeln("PNG ProcessChunk: Processing " ~ to!string(segment.chunkType));
        }

        // Compare checksums, but let chunk types determine how to handle failed checks
        bool csum_passed = true;
        uint csum_calc = crc32(0, segment.buffer[4..$-4]);
        uint csum_read = fourBytesToInt(segment.buffer[$-4..$]);
        if (csum_calc != csum_read)
        {
            csum_passed = false;
            debug
            {
                if (m_logging) writeln("PNG: Error - checksum failed!");
            }
        }

        switch(segment.chunkType)
        {
        case Chunk.IHDR: // IHDR chunk contains height, width info
        {
            if (!csum_passed)
            {
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
            m_pixelScale = 1;

            // This function sets some state, like m_nChannels
            allocateImage();

            // Calculate pixels per line and scanlines per pass for interlacing
            if (m_interlace == 1)
            {
                setInterlace();
            }

            auto bitStride = m_nChannels*m_bitDepth;
            auto imageBitsPerLine = m_width*bitStride;

            m_bytesPerScanline = 1 + imageBitsPerLine/8;
            m_stride = bitStride/8;

            if (imageBitsPerLine % 8 > 0)
            {
                m_bytesPerScanline ++;
                m_stride = 1;
            }

            if (m_stride == 0)
            {
                m_stride = 1;
            }

            // Initialize this scanLine, since it will be empty initially
            scanLine1 = new ubyte[](m_bytesPerScanline);

            debug
            {
                if (m_logging)
                {
                    writefln("PNG\n Width: %s\nHeight: %s\nBitDepth: %s\nColorType: %s\n"
                             "Compression: %s\nFilter: %s\nInterlacing: %s\nStride: %s",
                             m_width, m_height, m_bitDepth, m_colorType,
                             m_compression, m_filter, m_interlace, m_stride);
                }
            }
            break;
        }
        case Chunk.IDAT: // Actual image data
        {
            if (!csum_passed)
            {
                errorState.code = 1;
                errorState.message = "PNG: Checksum failed in IDAT!";
                return;
            }
            break;
        }
        case Chunk.PLTE: // Palette chunk
        {
            if (!csum_passed)
            {
                errorState.code = 1;
                errorState.message = "PNG: Checksum failed in IPLTE!";
                return;
            }

            if (m_colorType == 3)
                m_palette = segment.buffer[8..$-4].dup;

            break;
        }
        case Chunk.IEND: // Image end
        {
            // Flush out the rest of the stream
            uncompressStream(scanLine2, true);
            break;
        }

        default:
        {
            debug
            {
                if (m_logging) writeln("PNG ProcessChunk: Un-handled chunk " ~ to!string(segment.chunkType));
            }
            break;
        }
        }
    } // processChunk


    // Allocate the image
    void allocateImage()
    {
        switch (m_colorType)
        {
        case 0:   // greyscale
        {
            m_nChannels = 1;
            switch(m_bitDepth)
            {
            case 1:
                m_image = new Img!(Px.L8)(m_width, m_height);
                m_pixelScale = 255;
                break;
            case 2:
                m_image = new Img!(Px.L8)(m_width, m_height);
                m_pixelScale = 64;
                break;
            case 4:
                m_image = new Img!(Px.L8)(m_width, m_height);
                m_pixelScale = 16;
                break;
            case 8:
                m_image = new Img!(Px.L8)(m_width, m_height);
                break;
            case 16:
                m_image = new Img!(Px.L16)(m_width, m_height);
                break;
            default:
                m_errorState.code = 1;
                m_errorState.message = "PNG: Greyscale image with incorrect bit depth detected";
            }
            break;
        }
        case 2:   // rgb
        {
            m_nChannels = 3;
            switch(m_bitDepth)
            {
            case 8:
                m_image = new Img!(Px.R8G8B8)(m_width, m_height);
                break;
            case 16:
                m_image = new Img!(Px.R16G16B16)(m_width, m_height);
                break;
            default:
                m_errorState.code = 1;
                m_errorState.message = "PNG: RGB image with incorrect bit depth detected";
            }
            break;
        }
        case 3:   // palette
        {
            m_nChannels = 1;
            m_image = new Img!(Px.R8G8B8)(m_width, m_height);
            break;
        }
        case 4:   // greyscale + alpha
        {
            m_nChannels = 2;
            switch(m_bitDepth)
            {
            case 8:
                m_image = new Img!(Px.L8A8)(m_width, m_height);
                break;
            case 16:
                m_image = new Img!(Px.L16A16)(m_width, m_height);
                break;
            default:
                m_errorState.code = 1;
                m_errorState.message = "PNG: Greysca;+alpha with incorrect bit depth detected";
            }
            break;
        }
        case 6:   // rgba
        {
            m_nChannels = 4;
            switch(m_bitDepth)
            {
            case 8:
                m_image = new Img!(Px.R8G8B8A8)(m_width, m_height);
                break;
            case 16:
                m_image = new Img!(Px.R16G16B16A16)(m_width, m_height);
                break;
            default:
                m_errorState.code = 1;
                m_errorState.message = "PNG: RGBA image with incorrect bit depth detected";
            }
            break;
        }
        default: // error
            m_errorState.code = 1;
            m_errorState.message = "PNG: Incorrect color type detected";
        }
    } // allocateImage


    // Set some state dealing with interlacing
    void setInterlace()
    {
        foreach(i; 0..m_width)
        {
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

        foreach(i; 0..m_height)
        {
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
    } // setInterlace


    // Uncompress the stream, apply filters, and store image
    void uncompressStream(ubyte[] stream, bool finalize = false)
    {
        if (m_currentScanLine >= m_height || m_interlacePass >= 7)
            return;

        ubyte[] data;
        if (!finalize)
        {
            data = cast(ubyte[])(zliber.uncompress(cast(void[])stream));
        }
        else
        {   // finalize means flush out any remaining data
            data = cast(ubyte[])(zliber.flush());
        }

        // Number of bytes in a scanline depends on the interlace pass
        int bytesPerLine, nscanLines;
        passInfo(bytesPerLine, nscanLines);

        int taken = 0, takeLen = 0; // bytes taken, bytes to take
        while (taken < data.length)
        {
            // Put data into the lower scanline first
            takeLen = bytesPerLine - scanLine2.length;
            if (takeLen > 0 && taken + takeLen <= data.length)
            {
                scanLine2 ~= data[taken..taken+takeLen];
                taken += takeLen;
            }
            else if (takeLen > 0)
            {
                scanLine2 ~= data[taken..$];
                taken += data.length - taken;
            }

            if (scanLine2.length == bytesPerLine)
            {
                // Have a full scanline, so filter it...
                filter();

                auto scanLineStride = m_stride;

                // Unpack the bits if needed
                ubyte[] sLine;
                if (m_bitDepth < 8)
                {
                    sLine = unpackBits(scanLine2[1..$]);
                }
                else
                {
                    sLine = scanLine2[1..$];
                }

                // For palette colortypes, convert scanline to RGB
                if (m_colorType == 3)
                {
                    sLine = convertPaletteToRGB(sLine);
                    scanLineStride = 3;
                }

                // Scale the bits up to 0-255
                if (m_colorType != 3 && m_bitDepth < 8)
                {
                    sLine[] *= cast(ubyte)m_pixelScale;
                }

                // Put it into the Image
                if (m_interlace == 0)
                {
                    // Non-interlaced
                    m_image.setRow(m_currentScanLine, sLine);
                }
                else
                {
                    // Image is interlaced, so fill not just given pixels, but blocks of pixels
                    with(m_ilace)
                    {
                        int pass = m_interlacePass;
                        int col = start_col[pass]; // Image column
                        int i = 0; // scanline offset

                        while (col < m_width)
                        {
                            // Max x,y indices to fill up to for a given pass
                            auto maxY = min(block_height[pass], m_height - imageRow);
                            auto maxX = min(block_width[pass], m_width - col);

                            foreach(py; 0..maxY)
                            {
                                foreach(px; 0..maxX)
                                {
                                    m_image.setPixel(col + px, imageRow + py, sLine[i..i+scanLineStride]);
                                }
                            }

                            col = col + col_increment[pass];
                            i += scanLineStride;

                        } // while col < m_width
                    } // with(m_ilace)
                } // if m_interlace


                // Increment scanline counter
                m_currentScanLine ++;

                // Swap the scanlines
                auto tmp = scanLine1;
                scanLine1 = scanLine2;
                scanLine2 = scanLine1;
                scanLine2.clear;

                if (m_interlace == 1)
                {
                    m_ilace.imageRow += m_ilace.row_increment[m_interlacePass];
                }

                if (m_interlace == 1 && m_currentScanLine == nscanLines)
                {
                    m_currentScanLine = 0;
                    m_interlacePass ++;

                    if (m_interlacePass == 7 || m_currentScanLine >= m_height)
                    {
                        break;
                    }
                    else
                    {
                        scanLine1 = new ubyte[](m_bytesPerScanline);
                        m_ilace.imageRow = m_ilace.start_row[m_interlacePass];

                        // Recalc pass info
                        passInfo(bytesPerLine, nscanLines);
                    }
                }
            }

        } // while (taken < data.length)
    } // uncompressStream


    // Calculate some per-pass info
    void passInfo(out int bytesPerLine, out int nscanLines)
    {
        bytesPerLine = 0; // number of bytes in a scanline (dependent on interlace pass)
        nscanLines = 0; // number of scanlines (also depends on interlace pass)

        if (m_interlace == 1)
        {
            if (m_bitDepth < 8)
            {
                auto bitsPerLine = m_pixPerLine[m_interlacePass]*m_bitDepth;
                bytesPerLine = bitsPerLine/8;

                if (bitsPerLine % 8 > 0)
                {
                    bytesPerLine ++;
                }
                bytesPerLine ++; // need to acount for the filter-type byte
            }
            else
            {
                bytesPerLine = m_pixPerLine[m_interlacePass]*m_stride + 1;
            }

            nscanLines = m_scanLines[m_interlacePass];
        }
        else
        {
            bytesPerLine = m_bytesPerScanline;
            nscanLines = m_height;
        }
    } // passInfo


    // Unpack a scanline's worth of bits into a byte array
    ubyte[] unpackBits(ubyte[] data)
    {
        int bytesPerLine = 0;
        if (m_interlace == 0)
        {
            bytesPerLine = m_width;
        }
        else
        {
            bytesPerLine = m_pixPerLine[m_interlacePass];
        }

        ubyte[] unpacked;
        unpacked.length = bytesPerLine;

        auto data_index = 0, byte_index = 0;
        while(byte_index < bytesPerLine)
        {
            for(int j = 0; j < 8; j += m_bitDepth)
            {
                auto mask = ((1<<m_bitDepth)-1) << (8 - j - m_bitDepth);
                auto val = ((data[data_index] & mask) >> (8 - j - m_bitDepth));
                unpacked[byte_index] = cast(ubyte) val;
                byte_index ++;
                if (byte_index >= bytesPerLine)
                    break;
            }
            data_index ++;
        }

        return unpacked;
    } // unpackBits


    // Convert a scanline of palette values to a scanline of 8-bit RGB's
    ubyte[] convertPaletteToRGB(ubyte[] data)
    {
        ubyte[] rgb;
        rgb.length = data.length * 3;
        foreach(i; 0..data.length)
        {
            rgb[i*3] = m_palette[data[i]*3];
            rgb[i*3 + 1] = m_palette[data[i]*3 + 1];
            rgb[i*3 + 2] = m_palette[data[i]*3 + 2];
        }
        return rgb;
    } // convertPaletteToRGB


    // Apply filters to a scanline
    void filter()
    {
        int filterType = scanLine2[0];

        switch(filterType)
        {
        case 0:   // no filtering, excellent
        {
            break;
        }
        case 1:   // difference filter, using previous pixel on same scanline
        {
            filter1();
            break;
        }
        case 2:   // difference filter, using pixel on scanline above, same column
        {
            filter2();
            break;
        }
        case 3:   // average filter, average of pixel above and pixel to left
        {
            filter3();
            break;
        }
        case 4:   // Paeth filter
        {
            filter4();
            break;
        }
        default:
        {
            if (m_logging)
            {
                writeln("PNG: Unhandled filter (" ~ to!string(filterType) ~ ") on scan line "
                        ~ to!string(m_currentScanLine) ~ ", Pass: " ~ to!string(m_interlacePass));
            }
            break;
        }
        } // switch filterType
    }


    // Apply filter 1 to scanline (difference filter)
    void filter1()
    {
        // Can't use vector op because results need to accumulate
        for(int i=m_stride+1; i<scanLine2.length; i+=m_stride)
        {
            scanLine2[i..i+m_stride] += ( scanLine2[i-m_stride..i] );
        }
    }


    // Apply filter 2 to scanline (difference filter, using scanline above)
    void filter2()
    {
        scanLine2[1..$] += scanLine1[1..$];
    }


    // Apply filter 3 to scanline (average filter)
    void filter3()
    {
        scanLine2[1..1+m_stride] += cast(ubyte[])(scanLine1[1..1+m_stride] / 2);

        for(int i=m_stride+1; i<scanLine2.length; i+=m_stride)
        {
            scanLine2[i..i+m_stride] += cast(ubyte[])(( scanLine2[i-m_stride..i] +
                                        scanLine1[i..i+m_stride] ) / 2);
        }
    }


    // Apply filter 4 to scanline (Paeth filter)
    void filter4()
    {
        int paeth(ubyte a, ubyte b, ubyte c)
        {
            int p = (a + b - c);
            int pa = abs(p - a);
            int pb = abs(p - b);
            int pc = abs(p - c);

            int pred = 0;
            if ((pa <= pb) && (pa <= pc))
            {
                pred = a;
            }
            else if (pb <= pc)
            {
                pred = b;
            }
            else
            {
                pred = c;
            }
            return pred;
        }

        foreach(i; 1..m_stride+1)
        {
            scanLine2[i] += paeth(0, scanLine1[i], 0);
        }

        for(int i=m_stride+1; i<scanLine2.length; i+=m_stride)
        {
            foreach(j; 0..m_stride)
            {
                scanLine2[i+j] += paeth(scanLine2[i+j-m_stride], scanLine1[i+j], scanLine1[i+j-m_stride]);
            }
        }

    } // filter4
} // PngDecoder


/**
* PNG encoder for writing out Image classes to files as PNG.
* TODO: currently won't work with 16-bit Images.
*/
class PngEncoder : Encoder
{
    /**
    * Params:
    * img = the image containing the data to write as a png
    * filename = filename of the output
    * Returns: true if writing succeeded, else false.
    */
    bool write(in Image img, string filename)
    {
        ubyte[] outData = pngHeader.dup;

        // Add in image header info
        appendChunk(createHeaderChunk(img), outData);

        // Filter and compress the data
        auto rowLengthBytes = img.width*img.stride;

        // The first scanline - has nothing above it, limits filter options
        PNGChunk idat = PNGChunk("IDAT");
        ubyte[] imageData;
        ubyte[] scanLine1, scanLine2;
        scanLine1.length = rowLengthBytes; // initialize this scanline, since it will be empty to start

        foreach(row; 0..img.height)
        {
            scanLine2 = img.pixels[row*rowLengthBytes..(row+1)*rowLengthBytes].dup;

            // Apply adaptive filter
            ubyte filterType; // this will hold the actual filter that was used
            ubyte[] filtered = filter(img, scanLine1, scanLine2, filterType);
            imageData ~= filterType ~ filtered;

            // Swap the scanlines
            auto tmp = scanLine1;
            scanLine1 = scanLine2;
            scanLine2 = scanLine1;
            scanLine2.clear;
        }

        idat.data = cast(ubyte[]) compress(cast(void[])imageData);
        appendChunk(idat, outData);

        // End the image with an IEND
        appendChunk(PNGChunk("IEND"), outData);

        // Write the PNG
        std.file.write(filename, outData);

        return true;
    }

private:

    struct PNGChunk
    {
        string type;
        ubyte[] data;
    }

    // THe required PNG header
    immutable static ubyte[] pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    // Array of function pointers containing filter algorithms
    static ubyte[] function(in Image, in ubyte[], in ubyte[], out uint)[5] m_filters =
                                [&PngEncoder.filter0, &PngEncoder.filter1,
                                 &PngEncoder.filter2, &PngEncoder.filter3,
                                 &PngEncoder.filter4];

    /**
    * Determines which filter type to apply to a given scanline by simply trying all of them,
    * and calculating the sum of the absolute value in each filtered line. The filter which
    * gives the minimum absolute sum will be used.
    * Params:
    * scanLine1 = the scanline $(I above) the scanline to be filtered
    * scanLine2 = the scanline to be filtered
    * filterType = a variable to hold the actual filter type that was used
    * Returns: the filtered scanline
    */
    static ubyte[] filter(in Image img, in ubyte[] scanLine1, ubyte[] scanLine2, out ubyte filterType)
    {
        uint sum = 0, minSum = uint.max;
        ubyte[] filtered = scanLine2.dup;

        foreach(index, filter; m_filters)
        {
            auto s = filter(img, scanLine1, scanLine2, sum);
            if (sum < minSum)
            {
                filtered = s;
                minSum = sum;
                filterType = cast(ubyte)index;
            }
        }
        return filtered;
    }

    // Filter 0 means no filtering
    static ubyte[] filter0(in Image img, in ubyte[] scanLine1, in ubyte[] scanLine2, out uint absSum)
    {
        ubyte[] filtered = scanLine2.dup;
        absSum = reduce!("a + abs(b)")(0, filtered);
        return filtered;
    }

    // Filter 1 is a difference between the current pixel and the previous pixl on same scanline
    static ubyte[] filter1(in Image img, in ubyte[] scanLine1, in ubyte[] scanLine2, out uint absSum)
    {
        ubyte[] filtered = scanLine2.dup;
        uint s = img.stride;
        absSum = reduce!("a + abs(b)")(0, filtered[0..s]);
        for(int i = s; i < scanLine2.length; i++)
        {
            filtered[i] = cast(ubyte) (scanLine2[i] - scanLine2[i-s]);
            absSum += abs(filtered[i]);
        }
        return filtered;
    }

    // FIlter 2 is a difference between current pixel and same pixel on scanline above
    static ubyte[] filter2(in Image img, in ubyte[] scanLine1, in ubyte[] scanLine2, out uint absSum)
    {
        ubyte[] filtered = scanLine2.dup;
        filtered[] = scanLine2[] - scanLine1[];
        absSum = reduce!("a + abs(b)")(0, filtered);
        return filtered;
    }

    // Filter 3 is an average of previous pixel on same scanline ,and same pixel on line above
    static ubyte[] filter3(in Image img, in ubyte[] scanLine1, in ubyte[] scanLine2, out uint absSum)
    {
        ubyte[] filtered = scanLine2.dup;

        for(int i = 0; i < img.stride; i++)
        {
            filtered[i] = cast(ubyte) (scanLine2[i] - (scanLine1[i]/2) );
            absSum += abs(filtered[i]);
        }

        for(int i = img.stride; i < scanLine2.length; i++)
        {
            filtered[i] = cast(ubyte) (scanLine2[i] - (scanLine1[i]+scanLine2[i-img.stride])/2);
            absSum += abs(filtered[i]);
        }
        return filtered;
    }

    // Paeth filter
    static ubyte[] filter4(in Image img, in ubyte[] scanLine1, in ubyte[] scanLine2, out uint absSum)
    {
        int paeth(ubyte a, ubyte b, ubyte c)
        {
            int p = (a + b - c);
            int pa = abs(p - a);
            int pb = abs(p - b);
            int pc = abs(p - c);

            int pred = 0;
            if ((pa <= pb) && (pa <= pc))
            {
                pred = a;
            }
            else if (pb <= pc)
            {
                pred = b;
            }
            else
            {
                pred = c;
            }
            return pred;
        }

        ubyte[] filtered = scanLine2.dup;

        for(int i = 0; i < img.stride; i++)
        {
            filtered[i] = cast(ubyte) (scanLine2[i] - paeth(0, scanLine1[i], 0) );
            absSum += abs(filtered[i]);
        }

        for(int i = img.stride; i < scanLine2.length; i++)
        {
            filtered[i] = cast(ubyte) (scanLine2[i] - paeth(scanLine2[i-img.stride],
                                                            scanLine1[i],
                                                            scanLine1[i-img.stride]) );
            absSum += abs(filtered[i]);
        }
        return filtered;
    }

    // Create the header chunk
    PNGChunk createHeaderChunk(in Image img)
    {
        PNGChunk ihdr;
        ihdr.type = "IHDR";
        ihdr.data.length = 13;
        ihdr.data[0..4] = bigEndianBytes(img.width);
        ihdr.data[4..8] = bigEndianBytes(img.height);
        ihdr.data[8] = cast(ubyte)img.bitDepth;
        ihdr.data[9] = getColorType(img);
        ihdr.data[10..12] = [0,0];
        ihdr.data[12] = 0; // non-interlaced
        return ihdr;
    }

    // Append a chunk to the output data, fixing up endianness and calculating checksum
    void appendChunk(in PNGChunk chunk, ref ubyte[] data)
    {
        assert(chunk.type.length == 4);

        ubyte[] typeAndData = cast(ubyte[])chunk.type ~ chunk.data;
        uint checksum = crc32(0, typeAndData);

        data ~= bigEndianBytes(chunk.data.length) ~
                typeAndData ~
                bigEndianBytes(checksum);
    }

    // Figure out the PNG colortype of an image
    ubyte getColorType(in Image img)
    {
        ubyte colorType;
        if (img.pixelFormat == Px.L8 ||
            img.pixelFormat == Px.L16 )
        {
            colorType = 0;
        }
        else if (img.pixelFormat == Px.L8A8 ||
                 img.pixelFormat == Px.L16A16 )
        {
            colorType = 4;
        }
        else if (img.pixelFormat == Px.R8G8B8 ||
                 img.pixelFormat == Px.R16G16B16 )
        {
            colorType = 2;
        }
        else if (img.pixelFormat == Px.R8G8B8A8 ||
                 img.pixelFormat == Px.R16G16B16A16 )
        {
            colorType = 6;
        }
        else
        {
            assert(0);
        }
        return colorType;
    }

    // Convert a uint to corrct endianness for writing (must be in big endian for writing)
    version (LittleEndian)
    {
        ubyte[] bigEndian(in ubyte[] v)
        {
            return [v[3],v[2],v[1],v[0]];
        }
    }
    else // bigEndian version
    {
        ubyte[] bigEndian(in ubyte[] v)
        {
            return v;
        }
    }

    /**
    * Params: value: uint to convert to correct endianness
    * Returns: a ubyte[4] array, with proper endianness
    */
    ubyte[] bigEndianBytes(uint value)
    {
        uint[] inv = [value];
        ubyte[] v = cast(ubyte[])inv;
        return bigEndian(v);
    }
} // PngEncoder


