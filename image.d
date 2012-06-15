// Written in the D programming language.

/++
+ Copyright: Copyright 2012 -
+ License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+ Authors: Callum Anderson
+ Date: June 8, 2012
+/
module image;

import std.math, std.stdio, std.traits, std.conv, std.path;

import jpeg;
import png;


Image load(string filename) {

    Decoder dcd = null;

    switch(extension(filename)) {
        case(".jpg"):
        case(".jpeg"): dcd = new Jpeg(filename); break;
        case(".png"): dcd = new Png(filename); break;
        default: writeln("Imaged: no loader for extension " ~ extension(filename));
    }

    if (dcd is null) {
        return null;
    } else {
        return dcd.image;
    }
}


// Structure to report loading/decoding errors
struct IMGError {
    string message;
    int code;
}


// Container for RGBA values
struct Pixel {
    ushort r, g, b, a = 255;

    this(int r, int g, int b, int a = 255) {
        this.r = cast(ushort) r;
		this.g = cast(ushort) g;
		this.b = cast(ushort) b;
		this.a = cast(ushort) a;
	}
}


// Interface for an image decoder
abstract class Decoder {

    @property Image image() {return m_image; }
    @property IMGError errorState() {return m_errorState; }

protected:
    IMGError m_errorState;
    Image m_image;
}


// Interface for an Image
interface Image {

    // Algorithm for image resizing
    enum ResizeAlgo {
        CROP,
        NEAREST,
        BILINEAR,
        BICUBIC
    }

    Pixel opIndex(size_t x, size_t y);
    void setPixel(size_t x, size_t y, Pixel p);
    void setPixel(size_t x, size_t y, const(ubyte[]) data);
    void setRow(size_t y, const(ubyte[]) data);
    Image copy();
    bool resize(uint newWidth, uint newHeight, ResizeAlgo algo = ResizeAlgo.NEAREST);

    @property uint width();
    @property uint height();
    @property int stride();
    @property ref ubyte[] pixels();
    @property ubyte* pixelsPtr();
}


// Implementation for an image prameterized by number of channels and bits per channel
class ImageT(uint N /* N channels */, uint S /* Bits per channel */)
    if ((N <= 4) && ((S == 1) || (S == 2) || (S == 4) || (S == 8) || (S == 16))) : Image
{

    this(uint width, uint height, bool noAlloc = false) {
        m_width = width;
        m_height = height;
        m_channels = N;
        m_bitsPerChannel = S;
        m_pixelStride = N*cast(uint)(ceil(m_bitsPerChannel/8.0f));
        m_bitsPerPixel = N*S;

        if (!noAlloc) {
            m_data = new ubyte[](width*height*N*m_pixelStride);
        }
    }

    this(uint width, uint height, ubyte[] data, bool noCopy = false) {
        this(width, height, true);
        if (noCopy)
            m_data = data;
        else
            m_data = data.dup;
    }

    // Return a copy of this image, with buffer .dup'd
    ImageT!(N, S) copy() {
        auto copy = new ImageT!(N, S)(m_width, m_height, true);
        copy.pixels = m_data.dup;
        return copy;
    }

    // Get the pixel at (x, y), where y is relative to the bottom of the image
    Pixel opIndex(size_t x, size_t y) {
        uint i = xyToOffset(x,y);

        static if (N == 1 && S == 8) {
            return Pixel(m_data[i], 0, 0, 0);
        } else if (N == 3 && S == 8) {
            return Pixel(m_data[i], m_data[i+1], m_data[i+2], 0);
        } else if (N == 4 && S == 8) {
            return Pixel(m_data[i], m_data[i+1], m_data[i+2], m_data[i+3]);
        }
    }


    // Set the pixel at (x, y) to the given value
    void setPixel(size_t x, size_t y, Pixel p) {
        uint i = xyToOffset(x,y);

        static if (N == 1 && S == 8) {
            m_data[i] = cast(ubyte)p.r;
        } else if (N == 3 && S == 8) {
            m_data[i..i+3] = [cast(ubyte)p.r, cast(ubyte)p.g, cast(ubyte)p.b];
        } else if (N == 4 && S == 8) {
            m_data[i..i+4] = [cast(ubyte)p.r, cast(ubyte)p.g, cast(ubyte)p.b, cast(ubyte)p.a];
        }
    }

    void setPixel(size_t x, size_t y, const(ubyte[]) data) {}

    void setRow(size_t y, const(ubyte[]) data) {}

    /*
    * Resize an image to the given dimensions, using the given algorithm.
    * Returns: true on successful resize, else false.
    */
    bool resize(uint newWidth, uint newHeight, ResizeAlgo algo) {

        if (newWidth == m_width && newHeight == m_height)
            return false;

        // Create a delegate to define the resizing algorithm
        Pixel delegate(ImageT!(N,S), float, float, uint, uint) algorithmDelegate;

        if (algo == ResizeAlgo.NEAREST) {
            algorithmDelegate = &getNearestNeighbour;
        } else if (algo == ResizeAlgo.BILINEAR) {
            algorithmDelegate = &getBilinearInterpolate;
        } else if (algo == ResizeAlgo.CROP) {
            algorithmDelegate = &getCropped;
        } else {
            return false; // Algorithm not implemented!!
        }

        // Make a copy of the current image, this is the 'source'
        auto oldImg = this.copy();
        int oldWidth = oldImg.width;
        int oldHeight = oldImg.height;

        // Allocate a new array to hold the new image
        m_data = new ubyte[](newWidth*newHeight*m_pixelStride);
        m_width = newWidth;
        m_height = newHeight;

        uint i = 0; // 1D array index
        float x_ratio = cast(float)(oldWidth-1)/cast(float)(newWidth);
        float y_ratio = cast(float)(oldHeight-1)/cast(float)(newHeight);

        // Loop through rows and columns of the new image
        foreach (row; 0..newHeight) {
            foreach (col; 0..newWidth) {
                float x = x_ratio * cast(float)col;
                float y = y_ratio * cast(float)row;

                // Use the selected algorithm to get the pixel value
                Pixel p = algorithmDelegate(oldImg, x, y, col, row);

                // Store the new pixel
                static if (N == 1 && S == 8) {
                    m_data[i+col] = cast(ubyte)p.r;
                } else if (N == 3 && S == 8) {
                    m_data[(i+col)*3..(i+col)*3+3] = [cast(ubyte)p.r, cast(ubyte)p.g, cast(ubyte)p.b];
                } else if (N == 4 && S == 8) {
                    m_data[(i+col)*4..(i+col)*4+4] = [cast(ubyte)p.r, cast(ubyte)p.g, cast(ubyte)p.b, cast(ubyte)p.a];
                }
            } // columns
            i += m_width;
        }

        return true; // successfully resized
    } // resize


    // Getters
    @property uint width() { return m_width; } // ditto
    @property uint height() { return m_height; } // ditto
    @property int stride() { return m_pixelStride; } // ditto
    @property ref ubyte[] pixels() { return m_data; } // ditto
    @property ubyte* pixelsPtr() { return m_data.ptr; } // ditto


private:

    /**
    * This computes the 1D offset into the array for given (x,y).
    * Note that for images with < 8 bits per channel, this gives
    * the 1D index of the start of the _byte_.
    */
    uint xyToOffset(uint x, uint y) {
        static if (S < 8) {
            return (x + y*m_width)/(8/S);
        } else {
            return (x + y*m_width)*m_pixelStride;
        }
    }


    // Cropping algorithm - If (x,y) is in the original, return that pixel, else return 0,0,0,0
    Pixel getCropped(ImageT!(N,S) i, float x, float y, uint col, uint row) {
        if (col < i.width && row < i.height)
            return i[col, row];
        else
            return Pixel(0,0,0,0);
    }


    // Nearest neighbour sampling (actually just the nearest neighbour to the left and down)
    Pixel getNearestNeighbour(ImageT!(N,S) i, float x, float y, uint col, uint row) {
        int x0 = cast(int)x;
        int y0 = cast(int)y;
        return i[x0, y0];
    }

    /**
    * Calculate a bilinear interpolate at x, y. This implementation is from:
    * http://fastcpp.blogspot.com/2011/06/bilinear-pixel-interpolation-using-sse.html
    */
    Pixel getBilinearInterpolate(ImageT!(N,S) i, float x, float y, uint col, uint row) {

        int x0 = cast(int)x;
        int y0 = cast(int)y;

        // Weighting factors
        float fx = x - x0;
        float fy = y - y0;
        float fx1 = 1.0f - fx;
        float fy1 = 1.0f - fy;

        /** Get the locations in the src array of the 2x2 block surrounding (row,col)
        * 01 ------- 11
        * | (row,col) |
        * 00 ------- 10
        */
        Pixel p1 = i[x0, y0];
        Pixel p2 = i[x0+1, y0];
        Pixel p3 = i[x0, y0+1];
        Pixel p4 = i[x0+1, y0+1];

        int wgt1 = cast(int)(fx1 * fy1 * 256.0f);
        int wgt2 = cast(int)(fx  * fy1 * 256.0f);
        int wgt3 = cast(int)(fx1 * fy  * 256.0f);
        int wgt4 = cast(int)(fx  * fy  * 256.0f);

        int r = (p1.r * wgt1 + p2.r * wgt2 + p3.r * wgt3 + p4.r * wgt4) >> 8;
        int g = (p1.g * wgt1 + p2.g * wgt2 + p3.g * wgt3 + p4.g * wgt4) >> 8;
        int b = (p1.b * wgt1 + p2.b * wgt2 + p3.b * wgt3 + p4.b * wgt4) >> 8;
        int a = (p1.a * wgt1 + p2.a * wgt2 + p3.a * wgt3 + p4.a * wgt4) >> 8;

        return Pixel(cast(short)r, cast(short)g, cast(short)b, cast(short)a);
    }

    uint m_width, m_height;
    int m_channels;
    int m_bitsPerChannel;
    int m_bitsPerPixel;
    int m_pixelStride; // in bytes, minimum of 1
    ubyte[] m_data;
}











enum Px {
    L1,
    L2,
    L4,
    L8,
    L8A8,
    R8G8B8,
    R8G8B8A8,
    L16,
    L16A16,
    R16G16B16,
    R16G16B16A16
}

class Img(Px F) : Image {

    this(uint width, uint height) {

        m_scale = 1;
        static if (F == Px.L1) {
            m_bitDepth = 1; m_channels = 1; m_scale = 255;
        } else if (F == Px.L2) {
            m_bitDepth = 2; m_channels = 1; m_scale = 64;
        } else if (F == Px.L4) {
            m_bitDepth = 4; m_channels = 1;  m_scale = 16;
        } else if (F == Px.L8) {
            m_bitDepth = 8; m_channels = 1;
        } else if (F == Px.L8A8) {
            m_bitDepth = 8; m_channels = 2;
        } else if (F == Px.L8A8) {
            m_bitDepth = 8; m_channels = 2;
        } else if (F == Px.R8G8B8) {
            m_bitDepth = 8; m_channels = 3;
        } else if (F == Px.R8G8B8A8) {
            m_bitDepth = 8; m_channels = 4;
        } else if (F == Px.L16) {
            m_bitDepth = 16; m_channels = 1;
        } else if (F == Px.L16A16) {
            m_bitDepth = 16; m_channels = 2;
        } else if (F == Px.R16G16B16) {
            m_bitDepth = 16; m_channels = 3;
        } else if (F == Px.R16G16B16A16) {
            m_bitDepth = 16; m_channels = 4;
        }

        m_width = width;
        m_height = height;
        if (m_bitDepth < 8) {
            m_stride = m_channels;
        } else {
            m_stride = (m_bitDepth/8)*m_channels;
        }

        // Allocate data array
        m_data = new ubyte[](width*height*m_stride);
    }


    // Get the pixel at the given index
    Pixel opIndex(size_t x, size_t y) {

        auto index = getIndex(x, y);

        static if (F == Px.L1 ||
                   F == Px.L2 ||
                   F == Px.L4 ||
                   F == Px.L8) {
            auto v = m_data[index];
            return Pixel(v,v,v);

        } else if (F == Px.L8A8) {
            auto v = m_data[index];
            return Pixel(v, v, v, m_data[index+1]);

        } else if (F == Px.R8G8B8) {
            return Pixel(m_data[index],m_data[index+1],m_data[index+2]);

        } else if (F == Px.R8G8B8A8) {
            return Pixel(m_data[index],m_data[index+1],m_data[index+2],m_data[index+3]);

        } else if (F == Px.L16) {
            int v = m_data[index] << 8 | m_data[index+1];
            return Pixel(v,v,v,ushort.max);

        } else if (F == Px.L16A16) {
            int v = m_data[index] << 8 | m_data[index+1];
            int a = m_data[index+2] << 8 | m_data[index+3];
            return Pixel(v,v,v,a);

        } else if (F == Px.R16G16B16) {
            int r = m_data[index] << 8 | m_data[index+1];
            int g = m_data[index+2] << 8 | m_data[index+3];
            int b = m_data[index+4] << 8 | m_data[index+5];
            return Pixel(r,g,b,ushort.max);

        } else if (F == Px.R16G16B16A16) {
            int r = m_data[index] << 8 | m_data[index+1];
            int g = m_data[index+2] << 8 | m_data[index+3];
            int b = m_data[index+4] << 8 | m_data[index+5];
            int a = m_data[index+6] << 8 | m_data[index+7];
            return Pixel(r,g,b,a);
        }
    }


    // Set the pixel at the given index
    void setPixel(size_t x, size_t y, Pixel p) {

        auto index = getIndex(x, y);

        static if (F == Px.L1 ||
                   F == Px.L2 ||
                   F == Px.L4 ||
                   F == Px.L8) {
            m_data[index] = cast(ubyte)(p.r * m_scale);

        } else if (F == Px.L8A8) {
            m_data[index] = cast(ubyte)p.r;
            m_data[index+1] = cast(ubyte)p.a;

        } else if (F == Px.R8G8B8) {
            m_data[index] = cast(ubyte)p.r;
            m_data[index+1] = cast(ubyte)p.g;
            m_data[index+2] = cast(ubyte)p.b;

        } else if (F == Px.R8G8B8A8) {
            m_data[index] = cast(ubyte)p.r;
            m_data[index+1] = cast(ubyte)p.g;
            m_data[index+2] = cast(ubyte)p.b;
            m_data[index+3] = cast(ubyte)p.a;

        } else if (F == Px.L16) {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);

        } else if (F == Px.L16A16) {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);
            m_data[index+2] = cast(ubyte)(p.a >> 8);
            m_data[index+3] = cast(ubyte)(p.a & 0xFF);

        } else if (F == Px.R16G16B16) {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);
            m_data[index+2] = cast(ubyte)(p.g >> 8);
            m_data[index+3] = cast(ubyte)(p.g & 0xFF);
            m_data[index+4] = cast(ubyte)(p.b >> 8);
            m_data[index+5] = cast(ubyte)(p.b & 0xFF);

        } else if (F == Px.R16G16B16A16) {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);
            m_data[index+2] = cast(ubyte)(p.g >> 8);
            m_data[index+3] = cast(ubyte)(p.g & 0xFF);
            m_data[index+4] = cast(ubyte)(p.b >> 8);
            m_data[index+5] = cast(ubyte)(p.b & 0xFF);
            m_data[index+6] = cast(ubyte)(p.a >> 8);
            m_data[index+7] = cast(ubyte)(p.a & 0xFF);
        }

    }

    // Set the pixel at the given index
    void setPixel(size_t x, size_t y, const(ubyte[]) data) {

        auto index = getIndex(x, y);

        static if (F == Px.L1 ||
                   F == Px.L2 ||
                   F == Px.L4 ||
                   F == Px.L8) {
            setPixel(x, y, Pixel(data[0],0,0,0));

        } else if (F == Px.L8A8) {
            setPixel(x, y, Pixel(data[0],
                                 0,
                                 0,
                                 data[1]));

        } else if (F == Px.R8G8B8) {
            setPixel(x, y, Pixel(data[0],
                                 data[1],
                                 data[2],
                                 0));

        } else if (F == Px.R8G8B8A8) {
            setPixel(x, y, Pixel(data[0],
                                 data[1],
                                 data[2],
                                 data[3]));

        } else if (F == Px.L16) {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],0,0,0));

        } else if (F == Px.L16A16) {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],
                                 0,
                                 0,
                                 data[2] << 8 | data[3]));

        } else if (F == Px.R16G16B16) {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],
                                 data[2] << 8 | data[3],
                                 data[4] << 8 | data[5],
                                 0));

        } else if (F == Px.R16G16B16A16) {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],
                                 data[2] << 8 | data[3],
                                 data[4] << 8 | data[5],
                                 data[6] << 8 | data[7]));
        }
    }



    // Set a whole row (scanline) of data from the given buffer. Rows count down from the top.
    void setRow(size_t y, const(ubyte[]) data) {

        auto takeBits = m_width*m_bitDepth*m_channels;
        auto subBits = takeBits % 8;
        auto index = getIndex(0, y);

        debug { // Check array bounds if debug mode
            uint reqLen = takeBits / 8;
            if (subBits > 0) {
                reqLen ++;
            }
            if (data.length < reqLen) {
                writeln(takeBits/8, ", ", reqLen, ", ", data.length);
                throw new Exception("Image setRow: buffer does not have required length!");
            }
        }

        // Normal byte packing
        static if (F == Px.L8 ||
                   F == Px.L8A8 ||
                   F == Px.R8G8B8 ||
                   F == Px.R8G8B8A8 ||
                   F == Px.L16 ||
                   F == Px.L16A16 ||
                   F == Px.R16G16B16 ||
                   F == Px.R16G16B16A16 ) {

            m_data[index..index+(takeBits/8)] = data[0..(takeBits/8)];

        } else { // Sub-byte packing, need to loop through individual bytes and unpack

            foreach(bite; data) {
                for(int i=0; i<8; i+=m_bitDepth) {
                    int mask = ((1 << m_bitDepth) - 1) << (8 - i - m_bitDepth);
                    m_data[index] = cast(ubyte)(((bite & mask) >> (8 - i - m_bitDepth)) * m_scale);
                    index ++;
                }
            }
        }
    }


    Image copy() { return new Img!(F)(m_width, m_height); }

    bool resize(uint newWidth, uint newHeight, ResizeAlgo algo = ResizeAlgo.NEAREST) { return true;}

    // Getters
    @property uint width() { return m_width; } // ditto
    @property uint height() { return m_height; } // ditto
    @property int stride() { return m_stride; } // ditto
    @property ref ubyte[] pixels() { return m_data; } // ditto
    @property ubyte* pixelsPtr() { return m_data.ptr; } // ditto

private:

    // Get the byte index and bit offset for a given (x,y)
    uint getIndex(size_t x, size_t y) {
        return (x + y*m_width)*m_stride;
    }


    uint m_width = 0, m_height = 0;
    int m_stride = 0; // in bytes (minimum 1)
    int m_index = 0; // offset into data, in bits
    uint m_bitDepth = 0;
    uint m_channels = 0;
    int m_scale;
    ubyte[] m_data;
}

