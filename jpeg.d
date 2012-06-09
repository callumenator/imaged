// Written in the D programming language.

/++
+ Copyright: Copyright 2012 -
+ License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+ Authors: Callum Anderson
+ Date: June 6, 2012
+/
module jpeg;

import std.string, std.file, std.stdio, std.math,
       std.range, std.algorithm, std.conv;

import image;



/// Clamp an integer to 0-255 (ubyte)
ubyte clamp(const int x) {
    return (x < 0) ? 0 : ((x > 0xFF) ? 0xFF : cast(ubyte) x);
}

struct IMGError {
    string message;
    int code;
}

/**
* Jpeg class, which handles decoding. Great reference for baseline JPEG
* deconding: http://www.opennet.ru/docs/formats/jpeg.txt.
*/
class Jpeg {

    /// Markers courtesy of http://techstumbler.blogspot.com/2008/09/jpeg-marker-codes.html
    enum Marker
    {
        None = 0x00,

        // Start of Frame markers, non-differential, Huffman coding
        HuffBaselineDCT = 0xC0,
        HuffExtSequentialDCT = 0xC1,
        HuffProgressiveDCT = 0xC2,
        HuffLosslessSeq = 0xC3,

        // Start of Frame markers, differential, Huffman coding
        HuffDiffSequentialDCT = 0xC5,
        HuffDiffProgressiveDCT = 0xC6,
        HuffDiffLosslessSeq = 0xC7,

        // Start of Frame markers, non-differential, arithmetic coding
        ArthBaselineDCT = 0xC8,
        ArthExtSequentialDCT = 0xC9,
        ArthProgressiveDCT = 0xCA,
        ArthLosslessSeq = 0xCB,

        // Start of Frame markers, differential, arithmetic coding
        ArthDiffSequentialDCT = 0xCD,
        ArthDiffProgressiveDCT = 0xCE,
        ArthDiffLosslessSeq = 0xCF,

        // Huffman table spec
        HuffmanTableDef = 0xC4,

        // Arithmetic table spec
        ArithmeticTableDef = 0xCC,

        // Restart Interval termination
        RestartIntervalStart = 0xD0,
        RestartIntervalEnd = 0xD7,

        // Other markers
        StartOfImage = 0xD8,
        EndOfImage = 0xD9,
        StartOfScan = 0xDA,
        QuantTableDef = 0xDB,
        NumberOfLinesDef = 0xDC,
        RestartIntervalDef = 0xDD,
        HierarchProgressionDef = 0xDE,
        ExpandRefComponents = 0xDF,

        // Restarts
        Rst0 = 0xD0, Rst1 = 0xD1, Rst2 = 0xD2, Rst3 = 0xD3,
        Rst4 = 0xD4, Rst5 = 0xD5, Rst6 = 0xD6, Rst7 = 0xD7,

        // App segments
        App0 = 0xE0, App1 = 0xE1, App2 = 0xE2, App3 = 0xE3,
        App4 = 0xE4, App5 = 0xE5, App6 = 0xE6, App7 = 0xE7,
        App8 = 0xE8, App9 = 0xE9, App10 = 0xEA, App11 = 0xEB,
        App12 = 0xEC, App13 = 0xED, App14 = 0xEE, App15 = 0xEF,

        // Jpeg Extensions
        JpegExt0 = 0xF0, JpegExt1 = 0xF1, JpegExt2 = 0xF2, JpegExt3 = 0xF3,
        JpegExt4 = 0xF4, JpegExt5 = 0xF5, JpegExt6 = 0xF6, JpegExt7 = 0xF7,
        JpegExt8 = 0xF8, JpegExt9 = 0xF9, JpegExtA = 0xFA, JpegExtB = 0xFB,
        JpegExtC = 0xFC, JpegExtD = 0xFD,

        // Comments
        Comment = 0xFE,

        // Reserved
        ArithTemp = 0x01,
        ReservedStart = 0x02,
        ReservedEnd = 0xBF
    };

    /// Value at dctComponent[ix] should go to grid[block_order[ix]]
    immutable static ubyte[] block_order =
        [ 0,  1,  8, 16,  9,  2,  3, 10,   17, 24, 32, 25, 18, 11,  4,  5,
         12, 19, 26, 33, 40, 48, 41, 34,   27, 20, 13,  6,  7, 14, 21, 28,
         35, 42, 49, 56, 57, 50, 43, 36,   29, 22, 15, 23, 30, 37, 44, 51,
         58, 59, 52, 45, 38, 31, 39, 46,   53, 60, 61, 54, 47, 55, 62, 63 ];

    ulong totalBytesParsed = 0;
    ulong segmentBytesParsed = 0;
    Marker currentMarker = Marker.None;
    Marker previousMarker = Marker.None;
    bool markerPending = false;

    string format = "unknown"; /// File format (will only do JFIF)
    string type = "unknown";

    short x, y;
    ubyte nComponents, precision;
    Image RGB;
    struct Component {
        int id, /// component id
            qtt, /// quantization table id
            h_sample, /// horizontal samples
            v_sample; /// vertical samples
        ubyte[] data;
        int x, y, xi;
    }
    Component[] components;

    /// Store the image comment field if any
    char[] comment;

    /// Quantization Tables (hash map of vectors)
    ubyte[][int] quantTable;

    /// Huffman tables are stored in a hash map
    ubyte[16] nCodes; /// Number of codes of each bit length (cleared after each table is defined)
    struct hashKey { ubyte index; ubyte nBits; short bitCode; } /// Keys for the Huffman hash table
    ubyte[hashKey] huffmanTable;


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


    /// Parse a single byte
    void parse(ubyte bite) {

        segment.buffer ~= bite;

        if (bite == 0xFF) {
            markerPending = true;
            return;
        }

        if (markerPending) {

            markerPending = false;

            if (bite == 0x00) { /// This is an 0xFF value
                segment.buffer = segment.buffer[0..$-1];
                bite = 0xFF;
            } else if (bite >= 0xD0 && bite <= 0xD7) { /// Restart marker
                segment.buffer = segment.buffer[0..$-2];
                return;
            } else if (cast(Marker)bite == Marker.EndOfImage) {
                previousMarker = currentMarker;
                currentMarker = cast(Marker) bite;
                endOfImage();
                return;
            } else {
                previousMarker = currentMarker;
                currentMarker = cast(Marker) bite;
                segment = JPGSegment();
                return;
            }
        }

        if (!segment.headerProcessed) {

            if (segment.buffer.length == 2) {
                segment.headerLength = (segment.buffer[0] << 8 | segment.buffer[1]);
                return;
            } else if (segment.buffer.length == segment.headerLength) {
                writeln(currentMarker);
                processHeader();
                segment.headerProcessed = true;
                segment.buffer.clear;
                return;
            }
        } else {
            if (currentMarker == Marker.StartOfScan) {
                sosAction(bite);
            }
        }

        totalBytesParsed ++;
    } /// parse


private:

    /// Track the state of a scan segment
    struct ScanState {
        short cmpIdx = 0;

        int MCUWidth, MCUHeight; /// Dimensions of an MCU
        int nxMCU, nyMCU, xMCU, yMCU; /// Number of MCU's, and current MCU

        uint buffer = 0, bufferLength = 0, needBits = 0;
        bool comparing = true;
        ubyte[3] dct, act, nCmpBlocks;

        int[3] dcTerm;
        int[64] dctComponents;
        uint dctCmpIndex = 0, blockNumber = 0;
        int restartInterval;
        int MCUSParsed;
    }
    ScanState scState; /// ditto

    struct JPGSegment {
        bool headerProcessed;
        int headerLength;
        ubyte[] buffer;
    }


    JPGSegment segment;
    IMGError errorState;

    void YCbCrtoRGB(){}


    /// An empty action delegate
    void emptyAction() {}


    /// Process a segment header
    void processHeader() {

        /**
        * Remember: first two bytes in the buffer are the header length,
        * so header info starts at segment.buffer[2]!
        */
        switch(currentMarker) {

            /// Comment segment
            case(Marker.Comment): {

                comment = cast(char[])segment.buffer[2..$];

                debug {
                    writeln("JPEG: Comment: ", comment);
                }
                break;
            }

            /// App0, indicates JFIF format
            case(Marker.App0): {
                if (previousMarker == Marker.StartOfImage) {
                    format = "JFIF";
                }
                break;
            }

            /// Restart interval definition
            case(Marker.RestartIntervalDef): {

                scState.restartInterval = cast(int) (segment.buffer[2] << 8 | segment.buffer[3]);

                debug {
                    writeln("JPEG: Restart interval = ", scState.restartInterval);
                }
                break;
            }

            /// A quantization table definition
            case(Marker.QuantTableDef): {

                for (int i = 2; i < segment.buffer.length; i += 65) {
                    int precision = (segment.buffer[i] >> 4);
                    int index = (segment.buffer[i] & 0x0F);
                    quantTable[index] = segment.buffer[i+1..i+1+64].dup;

                    debug {
                        writefln("JPEG: Quantization table %s defined", index);
                    }
                }

                break;
            }

            /// Baseline frame
            case(Marker.HuffBaselineDCT): {

                ubyte precision = segment.buffer[2];
                y = cast(short) (segment.buffer[3] << 8 | segment.buffer[4]);
                x = cast(short) (segment.buffer[5] << 8 | segment.buffer[6]);
                nComponents = segment.buffer[7];
                components.length = nComponents;

                int i = 8;
                foreach(cmp; 0..nComponents) {
                    components[cmp].id = segment.buffer[i];
                    components[cmp].h_sample = (segment.buffer[i+1] >> 4);
                    components[cmp].v_sample = (segment.buffer[i+1] & 0x0F);
                    components[cmp].qtt = segment.buffer[i+2];
                    i += 3;

                    debug {
                        writefln("JPEG: Component %s defined", cmp);
                    }
                }

                break;
            }

            /// Huffman Table Definition, the mapping between bitcodes and Huffman codes
            case(Marker.HuffmanTableDef): {

                int i = 2;
                while (i < segment.buffer.length) {

                    ubyte index = segment.buffer[i]; /// Huffman table index
                    i ++;

                    auto nCodes = segment.buffer[i..i+16]; /// Number of codes at each tree depth
                    int totalCodes = reduce!("a + b")(0, nCodes); /// Sum up total codes, so we know when we are done
                    int storedCodes = 0;
                    i += 16;

                    ubyte huffmanRow = 0;
                    short huffmanCol = 0;
                    while (storedCodes != totalCodes) {

                        /**
                        * If nCodes is zero, we need to move down the table. The 'table'
                        * is basically a binary tree, seen as an array.
                        */
                        while (huffmanRow < 15 && nCodes[huffmanRow] == 0) {
                            huffmanRow ++;
                            huffmanCol *= 2;
                        }

                        if (huffmanRow < 16) {
                            /// Store the code into the hash table, using index, row and bitcode to make the key
                            hashKey key = { index:index, nBits:cast(ubyte)(huffmanRow+1), bitCode:huffmanCol};
                            huffmanTable[key] = segment.buffer[i];
                            storedCodes ++;
                            huffmanCol ++;
                            nCodes[huffmanRow] --;
                            i ++;
                        }
                    } /// while storedCodes != totalCodes
                }
                break;
            }

            /// StartOfScan (image data) header
            case(Marker.StartOfScan): {

                int scanComponents = segment.buffer[2]; /// Number of components in the scan

                if (scanComponents != nComponents) {
                    throw new Exception("JPEG: Scan components != image components!");
                }

                int i = 3;
                foreach (cmp; 0..scanComponents) {
                    ubyte id = cast(ubyte)(segment.buffer[i] - 1);
                    scState.dct[id] = segment.buffer[i+1] >> 4;   /// Component's DC huffman table
                    scState.act[id] = segment.buffer[i+1] & 0x0F; /// Component's AC huffman table
                }
                /// There is more to the header, but it is not needed


                /// Calculate MCU dimensions
                int v_samp_max = 0, h_samp_max = 0;
                foreach (cmp; components) {
                    if (cmp.h_sample > h_samp_max)
                        h_samp_max = cmp.h_sample;
                    if (cmp.v_sample > v_samp_max)
                        v_samp_max = cmp.v_sample;
                }
                scState.MCUWidth = h_samp_max*8;
                scState.MCUHeight = v_samp_max*8;

                /// Number of MCU's in the whole transformed image (the actual image could be smaller)
                scState.nxMCU = x / scState.MCUWidth;
                scState.nyMCU = y / scState.MCUHeight;
                if (x % scState.MCUWidth > 0)
                    scState.nxMCU ++;
                if (y % scState.MCUHeight > 0)
                    scState.nyMCU ++;

                /// Calculate the number of pixels for each component from the number of MCU's and sampling rate
                foreach (idx, ref cmp; components) {
                    cmp.x = scState.nxMCU * cmp.h_sample*8;
                    cmp.y = scState.nyMCU * cmp.v_sample*8;
                    cmp.data = new ubyte[](cmp.x*cmp.y);

                    debug {
                        writefln("Component %s, x:%s, y:%s", idx, cmp.x, cmp.y);
                    }
                }

                break;
            }

            default: {
                debug {
                    writeln("JPEG: ProcessHeader called on un-handled segment: ", currentMarker);
                }
                break;
            }
        }

    }


    /// Start of scan (image)
    void sosAction(ubyte bite) {

        /// Put the new bite into the buffer
        scState.buffer = scState.buffer << 8 | bite ;
        scState.bufferLength += 8;
        segment.buffer.clear;

        while (scState.bufferLength >= scState.needBits) {

            if (scState.comparing) {

                /// Try to get a Huffman code from the buffer
                ubyte* huffCode = fetchHuffmanCode(scState.buffer,
                                                    scState.bufferLength,
                                                    scState.needBits,
                                                    scState.cmpIdx);

                if (huffCode !is null) { /// Found a valid huffman code

                    /// Our buffer has effectively shrunk by the number of bits we just took
                    scState.bufferLength -= scState.needBits;
                    scState.needBits = 1;

                    processHuffmanCode(*huffCode);
                    continue;

                } else { /// Failed to get a Huffman code, try with more bits
                    scState.needBits ++;
                }

            } else { /// Not comparing, getting value bits

                if (scState.bufferLength < scState.needBits) continue; /// Need more bits in the buffer

                /// We have enough bits now to grab the value, so do that
                int dctComp = fetchDCTComponent(scState.buffer,
                                                scState.bufferLength,
                                                scState.needBits);

                /// Clear these bits from the buffer, set flag back to 'comparing'
                scState.bufferLength -= scState.needBits;
                scState.comparing = true;

                /// Put the new value into the component array
                scState.dctComponents[scState.dctCmpIndex] = dctComp;

                scState.dctCmpIndex ++; /// Increment our index in the components array
                if (scState.dctCmpIndex == 64) endOfBlock(); /// If we have reached the last index, this is end of block
                scState.needBits = 1; /// Reset the number of bits we need for comparing

            } // if !comparing
        } /// while bufferLength >= needBits
    } /// sosAction


    /// Check the buffer for a valid Huffman code
    ubyte* fetchHuffmanCode(int buffer, int bufferLength, int needBits, int componentIndex) {

        /// Create a mask to compare needBits bits in the buffer
        uint mask = ((1 << needBits) - 1) << (bufferLength-needBits);
        ushort bitCode = cast(ushort) ((mask & buffer) >> (bufferLength - needBits));

        ubyte tableId = 0;
        ubyte huffIndex = cast(ubyte) (componentIndex != 0);

        if (scState.dctCmpIndex != 0) { /// This is an AC component
            huffIndex += 16;
            tableId = scState.act[componentIndex];
        } else {                        /// This is a DC component
            tableId = scState.dct[componentIndex];
        }

        hashKey key = hashKey(huffIndex, cast(ubyte)needBits, bitCode);
        return (key in huffmanTable);

    } /// fetchHuffmanCode


    /// Process a Huffman code
    void processHuffmanCode(short huffCode) {

        if (huffCode == 0x00) { /// END OF BLOCK

            if (scState.dctCmpIndex == 0) { /// If we are on the DC term, don't call end of block...
                scState.dctCmpIndex ++; /// just increment the index
            } else {
                endOfBlock();
            }

        } else { /// Not an end of block

            /// The zero run length (not used for the DC component)
            ubyte preZeros = cast(ubyte) (huffCode >> 4);

            /// Increment the index by the number of preceeding zeros
            scState.dctCmpIndex += preZeros;

            /// The number of bits we need to get an actual value
            if (scState.dctCmpIndex == 64) { /// Check if we are at the end of the block
                endOfBlock();
            } else {
                scState.comparing = false; /// Not comparing bits anymore, waiting for a bitcode
                scState.needBits = cast(uint) (huffCode & 0x0F); /// Number of bits in the bitcode
            }
        }
    } /// processHuffmanCode


    /// Fetch the actual DCT component value
    int fetchDCTComponent(int buffer, int bufferLength, int needBits) {

        /// Create a mask to get the value from the (int) buffer
        uint mask = ((1 << needBits) - 1) << (bufferLength-needBits);
        short bits = cast(short) ((mask & buffer) >> (bufferLength - needBits));

        /// The first bit tells us which side of the value table we are on (- or +)
        int bit0 = bits >> (needBits-1);
        int offset = 2^^needBits;
        return (bits & ((1 << (needBits-1)) - 1)) + (bit0*offset/2 - (1-bit0)*(offset - 1));
    } /// fetchDCTComponent


    /// Have reached the end of a block, within a scan
    void endOfBlock() {

        /// Convert the DC value from relative to absolute
        scState.dctComponents[0] += scState.dcTerm[scState.cmpIdx];

        /// Store this block's DC term, to apply to the next block
        scState.dcTerm[scState.cmpIdx] = scState.dctComponents[0];

        /// Grab the quantization table for this component
        int[] qTable = to!(int[])(quantTable[components[scState.cmpIdx].qtt]);

        /// Dequantize the coefficients
        scState.dctComponents[] *= qTable[];

        /// Un zig-zag
        int[64] block;
        foreach (idx, elem; block_order) {
            block[elem] = scState.dctComponents[idx];
        }

        /// Calculate the offset into the component's pixel array
        int offset = 0;
        with (scState) {
            offset = xMCU*(components[cmpIdx].h_sample*8) +
                     yMCU*(components[cmpIdx].x)*(components[cmpIdx].v_sample*8);

            offset += 8*(blockNumber % 2) + 8*(blockNumber / 2)*components[cmpIdx].x;
        }

        /// The recieving buffer of the IDCT is then the component's pixel array
        ubyte* pix = components[scState.cmpIdx].data.ptr + offset;

        /// Do the inverse discrete cosine transform
        foreach(i; 0..8) colIDCT(block.ptr + i); // columns
        foreach(i; 0..8) rowIDCT(block.ptr + i*8, pix + i*components[scState.cmpIdx].x); // rows

        scState.dctCmpIndex = 0;
        scState.dctComponents[] = 0;
        scState.comparing = true;

        /// We have just decoded an 8x8 'block'
        scState.blockNumber ++;

        if (scState.blockNumber == components[scState.cmpIdx].h_sample*components[scState.cmpIdx].v_sample) {

            /// All the components in this block have been parsed
            scState.blockNumber = 0;
            scState.cmpIdx ++;

            if (scState.cmpIdx == nComponents) {
                /// All components in the MCU have been parsed, so increment
                scState.cmpIdx = 0;
                scState.MCUSParsed ++;
                scState.xMCU ++;
                if (scState.xMCU == scState.nxMCU) {
                    scState.xMCU = 0;
                    scState.yMCU ++;
                }
            }
        } /// if done all blocks for this component in the current MCU

        /// Check for restart marker
        if (scState.restartInterval != 0 && scState.MCUSParsed == scState.restartInterval) {

            /// We have come up to a restart marker, so reset the DC terms
            scState.dcTerm[] = 0;
            scState.MCUSParsed = 0;

            /// Need to skip all the bits up to the next byte boundary
            while (scState.bufferLength % 8 != 0) scState.bufferLength --;
        }

    } /// endOfBlock


    /// End of Image
    void endOfImage() {

        if (nComponents == 3) {

            Image Y = new ImageT!(1,8)(components[0].x, components[0].y, components[0].data);
            Image Cb = new ImageT!(1,8)(components[1].x, components[1].y, components[1].data);
            Image Cr = new ImageT!(1,8)(components[2].x, components[2].y, components[2].data);

            /// Resize the chroma components if required
            if (Cb.width != Y.width || Cb.height != Y.height)
                Cb.resize(Y.width, Y.height);

            if (Cr.width != Y.width || Cr.height != Y.height)
                Cr.resize(Y.width, Y.height);

            /// Convert to RGB
            RGB = new ImageT!(3,8)(Y.width, Y.height);

            foreach(y; 0..Y.height) {
                foreach(x; 0..Y.width) {
                    Pixel pix = Pixel(clamp(cast(int)(Y[x,y].r + 1.402*(Cr[x,y].r-128))),
                                      clamp(cast(int)(Y[x,y].r - 0.34414*(Cb[x,y].r-128) - 0.71414*(Cr[x,y].r-128) )),
                                      clamp(cast(int)(Y[x,y].r + 1.772*(Cb[x,y].r-128))),
                                      0);
                    RGB.setPixel(x,y,pix);
                }
            }

            //RGB = Image(R, G, B);
        }

        scState = ScanState();
        quantTable.clear;
        huffmanTable.clear;
        components.clear;


    } /// eoiAction


    /**
    * The following inverse discrete cosine transform (IDCT) voodoo comes from:
    * stbi-1.33 - public domain JPEG/PNG reader - http://nothings.org/stb_image.c
    */
    void colIDCT(int* block) {

        int x0,x1,x2,x3,t0,t1,t2,t3,p1,p2,p3,p4,p5;

        if (block[8] == 0 && block[16] == 0 && block[24] == 0 && block[32] == 0 &&
            block[40] == 0 && block[48] == 0 && block[56] == 0) {

                int dcterm = block[0] << 2;
                block[0] = block[8] = block[16] = block[24] =
                block[32] = block[40] = block[48] = block[56] = dcterm;
                return;
        }

        p2 = block[16];
        p3 = block[48];
        p1 = (p2+p3)*cast(int)(0.5411961f * 4096 + 0.5);
        t2 = p1 + p3*cast(int)(-1.847759065f * 4096 + 0.5);
        t3 = p1 + p2*cast(int)( 0.765366865f * 4096 + 0.5);
        p2 = block[0];
        p3 = block[32];
        t0 = (p2+p3) << 12;
        t1 = (p2-p3) << 12;
        x0 = t0+t3;
        x3 = t0-t3;
        x1 = t1+t2;
        x2 = t1-t2;
        t0 = block[56];
        t1 = block[40];
        t2 = block[24];
        t3 = block[8];
        p3 = t0+t2;
        p4 = t1+t3;
        p1 = t0+t3;
        p2 = t1+t2;
        p5 = (p3+p4)*cast(int)( 1.175875602f * 4096 + 0.5);
        t0 = t0*cast(int)( 0.298631336f * 4096 + 0.5);
        t1 = t1*cast(int)( 2.053119869f * 4096 + 0.5);
        t2 = t2*cast(int)( 3.072711026f * 4096 + 0.5);
        t3 = t3*cast(int)( 1.501321110f * 4096 + 0.5);
        p1 = p5 + p1*cast(int)(-0.899976223f * 4096 + 0.5);
        p2 = p5 + p2*cast(int)(-2.562915447f * 4096 + 0.5);
        p3 = p3*cast(int)(-1.961570560f * 4096 + 0.5);
        p4 = p4*cast(int)(-0.390180644f * 4096 + 0.5);
        t3 += p1+p4;
        t2 += p2+p3;
        t1 += p2+p4;
        t0 += p1+p3;

        x0 += 512; x1 += 512; x2 += 512; x3 += 512;
        block[0]  = (x0+t3) >> 10;
        block[56] = (x0-t3) >> 10;
        block[8]  = (x1+t2) >> 10;
        block[48] = (x1-t2) >> 10;
        block[16] = (x2+t1) >> 10;
        block[40] = (x2-t1) >> 10;
        block[24] = (x3+t0) >> 10;
        block[32] = (x3-t0) >> 10;
    } /// IDCT_1D_COL

    /// ditto
    void rowIDCT(int* block, ubyte* outData) {

        int x0,x1,x2,x3,t0,t1,t2,t3,p1,p2,p3,p4,p5;

        p2 = block[2];
        p3 = block[6];
        p1 = (p2+p3)*cast(int)(0.5411961f * 4096 + 0.5);
        t2 = p1 + p3*cast(int)(-1.847759065f * 4096 + 0.5);
        t3 = p1 + p2*cast(int)( 0.765366865f * 4096 + 0.5);
        p2 = block[0];
        p3 = block[4];
        t0 = (p2+p3) << 12;
        t1 = (p2-p3) << 12;
        x0 = t0+t3;
        x3 = t0-t3;
        x1 = t1+t2;
        x2 = t1-t2;
        t0 = block[7];
        t1 = block[5];
        t2 = block[3];
        t3 = block[1];
        p3 = t0+t2;
        p4 = t1+t3;
        p1 = t0+t3;
        p2 = t1+t2;
        p5 = (p3+p4)*cast(int)( 1.175875602f * 4096 + 0.5);
        t0 = t0*cast(int)( 0.298631336f * 4096 + 0.5);
        t1 = t1*cast(int)( 2.053119869f * 4096 + 0.5);
        t2 = t2*cast(int)( 3.072711026f * 4096 + 0.5);
        t3 = t3*cast(int)( 1.501321110f * 4096 + 0.5);
        p1 = p5 + p1*cast(int)(-0.899976223f * 4096 + 0.5);
        p2 = p5 + p2*cast(int)(-2.562915447f * 4096 + 0.5);
        p3 = p3*cast(int)(-1.961570560f * 4096 + 0.5);
        p4 = p4*cast(int)(-0.390180644f * 4096 + 0.5);
        t3 += p1+p4;
        t2 += p2+p3;
        t1 += p2+p4;
        t0 += p1+p3;

        x0 += 65536 + (128<<17);
        x1 += 65536 + (128<<17);
        x2 += 65536 + (128<<17);
        x3 += 65536 + (128<<17);

        outData[0] = clamp((x0+t3) >> 17);
        outData[7] = clamp((x0-t3) >> 17);
        outData[1] = clamp((x1+t2) >> 17);
        outData[6] = clamp((x1-t2) >> 17);
        outData[2] = clamp((x2+t1) >> 17);
        outData[5] = clamp((x2-t1) >> 17);
        outData[3] = clamp((x3+t0) >> 17);
        outData[4] = clamp((x3-t0) >> 17);
    } /// IDCT_1D_ROW
} /// class Jpeg
