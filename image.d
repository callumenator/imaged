// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Date: June 8, 2012
*/
module image;

import std.math, std.stdio, std.traits, std.conv, std.path;

import jpeg;
import png;


Image load(string filename)
{

    Decoder dcd = null;

    switch(extension(filename))
    {
    case(".jpg"):
    case(".jpeg"):
        dcd = new Jpeg(filename);
        break;
    case(".png"):
        dcd = new Png(filename);
        break;
    default:
        writeln("Imaged: no loader for extension " ~ extension(filename));
    }

    if (dcd is null)
    {
        return null;
    }
    else
    {
        return dcd.image;
    }
}


// Structure to report loading/decoding errors
struct IMGError
{
    string message;
    int code;
}


// Container for RGBA values
struct Pixel
{
    ushort r, g, b, a = 255;

    this(int r, int g, int b, int a = 255)
    {
        this.r = cast(ushort) r;
        this.g = cast(ushort) g;
        this.b = cast(ushort) b;
        this.a = cast(ushort) a;
    }
}


// Interface for an image decoder
abstract class Decoder
{

    @property Image image()
    {
        return m_image;
    }
    @property IMGError errorState()
    {
        return m_errorState;
    }

protected:
    IMGError m_errorState;
    Image m_image;
}


enum Px
{
    L8,
    L8A8,
    R8G8B8,
    R8G8B8A8,
    L16,
    L16A16,
    R16G16B16,
    R16G16B16A16
}


// Interface for an Image
interface Image
{

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

class Img(Px F) : Image
{
    this(uint width, uint height)
    {
        static if (F == Px.L8)
        {
            m_bitDepth = 8;
            m_channels = 1;
        }
        else if (F == Px.L8A8)
        {
            m_bitDepth = 8;
            m_channels = 2;
        }
        else if (F == Px.L8A8)
        {
            m_bitDepth = 8;
            m_channels = 2;
        }
        else if (F == Px.R8G8B8)
        {
            m_bitDepth = 8;
            m_channels = 3;
        }
        else if (F == Px.R8G8B8A8)
        {
            m_bitDepth = 8;
            m_channels = 4;
        }
        else if (F == Px.L16)
        {
            m_bitDepth = 16;
            m_channels = 1;
        }
        else if (F == Px.L16A16)
        {
            m_bitDepth = 16;
            m_channels = 2;
        }
        else if (F == Px.R16G16B16)
        {
            m_bitDepth = 16;
            m_channels = 3;
        }
        else if (F == Px.R16G16B16A16)
        {
            m_bitDepth = 16;
            m_channels = 4;
        }

        m_width = width;
        m_height = height;
        m_stride = (m_bitDepth/8)*m_channels;

        // Allocate data array
        m_data = new ubyte[](width*height*m_stride);
    }


    // Get the pixel at the given index
    Pixel opIndex(size_t x, size_t y)
    {

        auto index = getIndex(x, y);

        static if (F == Px.L8)
        {
            auto v = m_data[index];
            return Pixel(v,v,v);
        }
        else if (F == Px.L8A8)
        {
            auto v = m_data[index];
            return Pixel(v, v, v, m_data[index+1]);
        }
        else if (F == Px.R8G8B8)
        {
            return Pixel(m_data[index],m_data[index+1],m_data[index+2]);
        }
        else if (F == Px.R8G8B8A8)
        {
            return Pixel(m_data[index],m_data[index+1],m_data[index+2],m_data[index+3]);
        }
        else if (F == Px.L16)
        {
            int v = m_data[index] << 8 | m_data[index+1];
            return Pixel(v,v,v,ushort.max);
        }
        else if (F == Px.L16A16)
        {
            int v = m_data[index] << 8 | m_data[index+1];
            int a = m_data[index+2] << 8 | m_data[index+3];
            return Pixel(v,v,v,a);
        }
        else if (F == Px.R16G16B16)
        {
            int r = m_data[index] << 8 | m_data[index+1];
            int g = m_data[index+2] << 8 | m_data[index+3];
            int b = m_data[index+4] << 8 | m_data[index+5];
            return Pixel(r,g,b,ushort.max);
        }
        else if (F == Px.R16G16B16A16)
        {
            int r = m_data[index] << 8 | m_data[index+1];
            int g = m_data[index+2] << 8 | m_data[index+3];
            int b = m_data[index+4] << 8 | m_data[index+5];
            int a = m_data[index+6] << 8 | m_data[index+7];
            return Pixel(r,g,b,a);
        }
    }


    // Set the pixel at the given index
    void setPixel(size_t x, size_t y, Pixel p)
    {
        auto index = getIndex(x, y);

        static if (F == Px.L8)
        {
            m_data[index] = cast(ubyte)p.r;
        }
        else if (F == Px.L8A8)
        {
            m_data[index] = cast(ubyte)p.r;
            m_data[index+1] = cast(ubyte)p.a;
        }
        else if (F == Px.R8G8B8)
        {
            m_data[index] = cast(ubyte)p.r;
            m_data[index+1] = cast(ubyte)p.g;
            m_data[index+2] = cast(ubyte)p.b;
        }
        else if (F == Px.R8G8B8A8)
        {
            m_data[index] = cast(ubyte)p.r;
            m_data[index+1] = cast(ubyte)p.g;
            m_data[index+2] = cast(ubyte)p.b;
            m_data[index+3] = cast(ubyte)p.a;
        }
        else if (F == Px.L16)
        {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);
        }
        else if (F == Px.L16A16)
        {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);
            m_data[index+2] = cast(ubyte)(p.a >> 8);
            m_data[index+3] = cast(ubyte)(p.a & 0xFF);
        }
        else if (F == Px.R16G16B16)
        {
            m_data[index] = cast(ubyte)(p.r >> 8);
            m_data[index+1] = cast(ubyte)(p.r & 0xFF);
            m_data[index+2] = cast(ubyte)(p.g >> 8);
            m_data[index+3] = cast(ubyte)(p.g & 0xFF);
            m_data[index+4] = cast(ubyte)(p.b >> 8);
            m_data[index+5] = cast(ubyte)(p.b & 0xFF);
        }
        else if (F == Px.R16G16B16A16)
        {
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
    void setPixel(size_t x, size_t y, const(ubyte[]) data)
    {

        auto index = getIndex(x, y);

        static if (F == Px.L8)
        {
            setPixel(x, y, Pixel(data[0],0,0,0));
        }
        else if (F == Px.L8A8)
        {
            setPixel(x, y, Pixel(data[0],
                                 0,
                                 0,
                                 data[1]));
        }
        else if (F == Px.R8G8B8)
        {
            setPixel(x, y, Pixel(data[0],
                                 data[1],
                                 data[2],
                                 0));
        }
        else if (F == Px.R8G8B8A8)
        {
            setPixel(x, y, Pixel(data[0],
                                 data[1],
                                 data[2],
                                 data[3]));
        }
        else if (F == Px.L16)
        {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],0,0,0));
        }
        else if (F == Px.L16A16)
        {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],
                                 0,
                                 0,
                                 data[2] << 8 | data[3]));
        }
        else if (F == Px.R16G16B16)
        {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],
                                 data[2] << 8 | data[3],
                                 data[4] << 8 | data[5],
                                 0));
        }
        else if (F == Px.R16G16B16A16)
        {
            setPixel(x, y, Pixel(data[0] << 8 | data[1],
                                 data[2] << 8 | data[3],
                                 data[4] << 8 | data[5],
                                 data[6] << 8 | data[7]));
        }
    }



    // Set a whole row (scanline) of data from the given buffer. Rows count down from the top.
    void setRow(size_t y, const(ubyte[]) data)
    {
        auto takeBytes = m_width*m_stride;
        auto index = getIndex(0, y);

        debug   // Check array bounds if debug mode
        {
            if (data.length < takeBytes)
            {
                writeln(takeBytes, ", ", data.length);
                throw new Exception("Image setRow: buffer does not have required length!");
            }
        }
        m_data[index..index+takeBytes] = data[];
    }


    // Return an Image which is a copy of this one
    Img!F copy()
    {
        auto copy = new Img!F(m_width, m_height);
        copy.pixels = m_data.dup;
        return copy;
    }


    /*
    * Resize an image to the given dimensions, using the given algorithm.
    * Returns: true on successful resize, else false.
    */
    bool resize(uint newWidth, uint newHeight, ResizeAlgo algo)
    {
        // If new dimensions are same as old ones, flag success
        if (newWidth == m_width && newHeight == m_height)
        {
            return true;
        }

        // Create a delegate to define the resizing algorithm
        ushort[4] delegate(Img!F, float, float, uint, uint) algorithmDelegate;

        if (algo == ResizeAlgo.NEAREST)
        {
            algorithmDelegate = &getNearestNeighbour;
        }
        else if (algo == ResizeAlgo.BILINEAR)
        {
            algorithmDelegate = &getBilinearInterpolate;
        }
        else if (algo == ResizeAlgo.CROP)
        {
            algorithmDelegate = &getCropped;
        }
        else
        {
            return false; // Algorithm not implemented!!
        }

        // Make a copy of the current image, this is the 'source'
        auto oldImg = this.copy();
        int oldWidth = oldImg.width;
        int oldHeight = oldImg.height;

        // Allocate a new array to hold the new image
        m_data = new ubyte[](newWidth*newHeight*m_stride);
        m_width = newWidth;
        m_height = newHeight;

        uint i = 0; // 1D array index
        float x_ratio = cast(float)(oldWidth-1)/cast(float)(newWidth);
        float y_ratio = cast(float)(oldHeight-1)/cast(float)(newHeight);

        // Loop through rows and columns of the new image
        foreach (row; 0..newHeight)
        {
            foreach (col; 0..newWidth)
            {
                float x = x_ratio * cast(float)col;
                float y = y_ratio * cast(float)row;

                // Use the selected algorithm to get the pixel value
                ushort[4] p = algorithmDelegate(oldImg, x, y, col, row);

                // Store the new pixel
                static if (F == Px.L8)
                {
                    m_data[i+col] = cast(ubyte)p[0];
                }
                else if (F == Px.L8A8 ||
                         F == Px.R8G8B8 ||
                         F == Px.R8G8B8A8 )
                {
                    m_data[(i+col)*m_stride..(i+col + 1)*m_stride] = to!(ubyte[])(p[0..m_stride]);
                }
                else if (F == Px.L16)
                {
                    m_data[(i+col)*m_stride..(i+col + 1)*m_stride] = [p[0] >> 8, p[0] & 0xFF];
                }
                else if (F == Px.L16A16)
                {
                    m_data[(i+col)*m_stride..(i+col + 1)*m_stride] = [p[0] >> 8, p[0] & 0xFF,
                                                                      p[3] >> 8, p[3] & 0xFF];
                }
                else if (F == Px.R16G16B16)
                {
                    m_data[(i+col)*m_stride..(i+col + 1)*m_stride] = [p[0] >> 8, p[0] & 0xFF,
                                                                      p[1] >> 8, p[1] & 0xFF,
                                                                      p[2] >> 8, p[2] & 0xFF];
                }
                else if (F == Px.R16G16B16A16)
                {
                    m_data[(i+col)*m_stride..(i+col + 1)*m_stride] = [p[0] >> 8, p[0] & 0xFF,
                                                                      p[1] >> 8, p[1] & 0xFF,
                                                                      p[2] >> 8, p[2] & 0xFF,
                                                                      p[3] >> 8, p[3] & 0xFF];
                }

            } // columns
            i += m_width;
        }

        return true; // successfully resized
    } // resize

    // Getters
    @property uint width()
    {
        return m_width;    // ditto
    }
    @property uint height()
    {
        return m_height;    // ditto
    }
    @property int stride()
    {
        return m_stride;    // ditto
    }
    @property ref ubyte[] pixels()
    {
        return m_data;    // ditto
    }
    @property ubyte* pixelsPtr()
    {
        return m_data.ptr;    // ditto
    }

private:


    // Get the byte index and bit offset for a given (x,y)
    uint getIndex(size_t x, size_t y)
    {
        return (x + y*m_width)*m_stride;
    }


    // Cropping algorithm - If (x,y) is in the original, return that pixel, else return 0,0,0,0
    ushort[4] getCropped(Img!F i, float x, float y, uint col, uint row)
    {
        Pixel p;
        if (col < i.width && row < i.height)
        {
            p = i[col, row];
        }
        else
        {
            p = Pixel(0,0,0); // note: alpha is left as default here, so it will appear black
        }
        return [p.r, p.g, p.b, p.a];
    }


    // Nearest neighbour sampling (actually just the nearest neighbour to the left and down)
    ushort[4] getNearestNeighbour(Img!F i, float x, float y, uint col, uint row)
    {
        int x0 = cast(int)x;
        int y0 = cast(int)y;
        Pixel p = i[x0, y0];
        return [p.r, p.g, p.b, p.a];
    }

    /**
    * Calculate a bilinear interpolate at x, y. This implementation is from:
    * http://fastcpp.blogspot.com/2011/06/bilinear-pixel-interpolation-using-sse.html
    */
    ushort[4] getBilinearInterpolate(Img!F i, float x, float y, uint col, uint row)
    {
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

        return [cast(short)r, cast(short)g, cast(short)b, cast(short)a];
    }

    uint m_width = 0, m_height = 0;
    int m_stride = 0; // in bytes (minimum 1)
    uint m_bitDepth = 0;
    uint m_channels = 0;
    ubyte[] m_data;
}

