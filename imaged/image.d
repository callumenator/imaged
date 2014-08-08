// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Date: June 8, 2012
*/
module imaged.image;

import
    std.file,
    std.math,
    std.stdio,
    std.conv,
    std.path,
    std.stream;

import
    imaged.jpeg,
    imaged.png;


// Convenience function for loading from a file
Image load(string filename, out IMGError err, bool logging = false)
{
    Decoder dcd = getDecoder(filename, logging);

    if (dcd is null)
    {
        return null;
    }
    else
    {
        err = dcd.errorState;
        dcd.parseFile(filename);
        return dcd.image;
    }
}


// Convenience function for getting a decoder for a given filename
Decoder getDecoder(string filename, bool logging = false)
{
    Decoder dcd = null;

    switch(extension(filename))
    {
    case ".jpg":
    case ".jpeg": dcd = new JpegDecoder(logging); break;
    case ".png":  dcd = new PngDecoder(logging);  break;
    default: writeln("Imaged: no loader for extension " ~ extension(filename));
    }
    return dcd;
}

// Convenience function for getting an encoder for a given filename
Encoder getEncoder(string filename)
{
    Encoder enc = null;

    switch(extension(filename))
    {
    case ".png":  enc = new PngEncoder();  break;
    default: writeln("Imaged: no loader for extension " ~ extension(filename));
    }
    return enc;
}


/**
* The functions below allow you to create an OpenGL texture from an Image, and then
* throw away the image. These functions assume that you have already called DerelictGL.load().
*/
version(OpenGL)
{
    import derelict.opengl3.gl;

    /**
    * Set internal format to force a specific format, else the format will
    * be chosen based on the image type.
    */
    GLuint loadTexture(string filename, GLuint internalFormat = 0,
                                        bool logging = false,
                                        IMGError err = IMGError())
    {
        // Keep a static lookup table for images/textures which have already been loaded
        static GLuint[string] loadedTextures;

        auto ptr = filename in loadedTextures;
        if (ptr !is null)
        {
            // Texture has already been loaded, just return the GL handle
            return *ptr;
        }
        else
        {
            // Load the texture and store it in the lookup table
            GLuint tex = makeGLTexture(filename, internalFormat, logging, err);
            loadedTextures[filename] = tex;
            return tex;
        }
    }

    GLuint makeGLTexture(string filename, GLuint internalFormat = 0,
                                          bool logging = false,
                                          IMGError err = IMGError())
    {
        debug { writeln("Making GL Texture from: " ~ filename); }

        GLuint tex = 0;
        GLenum texformat;
        GLint nchannels;

        glGenTextures(1, &tex);
        auto img = load(filename, err, logging);

        if (img.pixelFormat == Px.R8G8B8)
        {
            nchannels = 3;
            texformat = GL_RGB;
            debug { writeln("Texture format is: GL_RGB"); }
        }
        else if (img.pixelFormat == Px.R8G8B8A8)
        {
            nchannels = 4;
            texformat = GL_RGBA;
            debug { writeln("Texture format is: GL_RGBA"); }
        }
        else if (img.pixelFormat == Px.L8)
        {
            nchannels = 1;
            texformat = GL_LUMINANCE;
            debug { writeln("Texture format is: GL_LUMINANCE"); }
        }

        GLuint useFormat = nchannels;
        if (internalFormat != 0)
            useFormat = internalFormat;

        /// Bind the texture object.
        glBindTexture(GL_TEXTURE_2D, tex);

        /// Set the texture interp properties.
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        /// Create the tex data.
        if (DerelictGL3.loadedVersion < GLVersion.GL30)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, GL_TRUE);
            glTexImage2D(GL_TEXTURE_2D, 0, useFormat, cast(int)img.width, cast(int)img.height, 0,
                         texformat, GL_UNSIGNED_BYTE, img.pixels.ptr);
        }
        else
        {
            glTexImage2D(GL_TEXTURE_2D, 0, useFormat, cast(int)img.width, cast(int)img.height, 0,
                         texformat, GL_UNSIGNED_BYTE, img.pixels.ptr);
            glGenerateMipmap(GL_TEXTURE_2D);
        }

        return tex;
    } // makeGLTexture
}


// Structure to report loading/decoding errors
struct IMGError
{
    string message;
    int code;
}


// Interface for an image decoder
abstract class Decoder
{
    // Parse a single byte
    void parseByte(ubyte bite);


    // Parse a file directly
    void parseFile(in string filename)
    {
        // Loop through the image data
        auto data = cast(ubyte[]) read(filename);
        foreach (bite; data)
        {
            if (m_errorState.code == 0)
            {
                parseByte(bite);
            }
            else
            {
                debug
                {
                    if (m_logging) writeln("IMAGE ERROR: ", m_errorState.message);
                }
                break;
            }
        }
    } // parseFile


    // Parse from the stream. Returns the amount of data left in the stream.
    size_t parseStream(Stream stream, in size_t chunkSize = 100000)
    {
        if (!stream.readable)
        {
            m_errorState.code = 1;
            m_errorState.message = "DECODER: Stream is not readable";
            return 0;
        }

        ubyte[] buffer;
        buffer.length = chunkSize;
        size_t rlen = stream.readBlock(cast(void*)buffer.ptr, chunkSize*ubyte.sizeof);
        if (rlen)
        {
            foreach(bite; buffer)
            {
                if (m_errorState.code != 0)
                {
                    rlen = 0;
                    break;
                }
                parseByte(bite);
            }
        }
        return rlen;
    }

    // Getters
    @property Image image() { return m_image; }
    @property IMGError errorState() const { return m_errorState; } // ditto

protected:
    bool m_logging = false; // if true, will emit logs when in debug mode
    IMGError m_errorState;
    Image m_image;
}


// Interface for an image encoder
abstract class Encoder
{
    bool write(in Image img, string filename);
}


// Currently allowed pixel formats
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

// Enumerate the image formats
enum ImageFormat
{
    GETFROMEXTENSION,
    PNG,
    JPG,
    JPEG
}


// Container for RGBA values
struct Pixel
{
    /**
    * Note that alpha defaults to opaque for _8 bit_ formats.
    * For 16 bit formats, be aware of this.
    */
    ushort r, g, b, a = 255;

    this(int r, int g, int b, int a = 255)
    {
        this.r = cast(ushort) r;
        this.g = cast(ushort) g;
        this.b = cast(ushort) b;
        this.a = cast(ushort) a;
    }
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

    // Overload index operator to return pixel at (x,y) coords (y is measured from the top down)
    Pixel opIndex(size_t x, size_t y, bool scaleToByte = true);

    // Simply calls opIndex
    Pixel getPixel(size_t x, size_t y, bool scaleToByte = true);

    // Set the pixel at (x,y) from the given Pixel
    void setPixel(size_t x, size_t y, Pixel p);

    // Set the pixel at (x,y) from the given ubyte array
    void setPixel(size_t x, size_t y, const(ubyte[]) data);

    // Set a complete row of the image, from the supplied buffer
    void setRow(size_t y, const(ubyte[]) data);

    // Return a copy of the current image
    Image copy() const;

    // Resize the image, either by cropping, nearest neighbor or bilinear algorithms
    bool resize(uint newWidth, uint newHeight, ResizeAlgo algo = ResizeAlgo.NEAREST);

    // Write image to disk as
    bool write(string filename, ImageFormat fmt = ImageFormat.GETFROMEXTENSION);

    // Getters
    @property const(uint) width() const;
    @property const(uint) height() const; // ditto
    @property const(int) stride() const; // ditto
    @property const(uint) bitDepth() const; // ditto
    @property const(Px) pixelFormat() const; // ditto
    @property const(ubyte[]) pixels() const; // ditto
    @property ref ubyte[] pixels(); // ditto
    @property ubyte* pixelsPtr(); // ditto
}


// The image class backend, parameterized by pixel format
class Img(Px F) : Image
{
    this(uint width, uint height, bool noAlloc = false)
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
        if (!noAlloc)
            m_data = new ubyte[](width*height*m_stride);
    }


    // Create an image using a pre-existing buffer
    this(uint width, uint height, ubyte[] data)
    {
        this(width, height, true);
        m_data = data;
    }


    /**
    * Get the pixel at the given index. If scaleToByte is set,
    * 16 bit formats will only return the high bytes, effectively
    * reducing precision to 8bit.
    */
    Pixel opIndex(size_t x, size_t y, bool scaleToByte = true)
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
            int v;
            if (scaleToByte)
            {
                v = m_data[index];
                return Pixel(v,v,v,ubyte.max);
            }
            else
            {
                v = m_data[index] << 8 | m_data[index+1];
                return Pixel(v,v,v,ushort.max);
            }

        }
        else if (F == Px.L16A16)
        {
            int v, a;
            if (scaleToByte)
            {
                v = m_data[index];
                a = m_data[index+2];
            }
            else
            {
                v = m_data[index] << 8 | m_data[index+1];
                a = m_data[index+2] << 8 | m_data[index+3];
            }
            return Pixel(v,v,v,a);
        }
        else if (F == Px.R16G16B16)
        {
            int r, g, b;
            if (scaleToByte)
            {
                r = m_data[index];
                g = m_data[index+2];
                b = m_data[index+4];
                return Pixel(r,g,b,ubyte.max);
            }
            else
            {
                r = m_data[index] << 8 | m_data[index+1];
                g = m_data[index+2] << 8 | m_data[index+3];
                b = m_data[index+4] << 8 | m_data[index+5];
                return Pixel(r,g,b,ushort.max);
            }
        }
        else if (F == Px.R16G16B16A16)
        {
            int r, g, b, a;
            if (scaleToByte)
            {
                r = m_data[index];
                g = m_data[index+2];
                b = m_data[index+4];
                a = m_data[index+6];
            }
            else
            {
                r = m_data[index] << 8 | m_data[index+1];
                g = m_data[index+2] << 8 | m_data[index+3];
                b = m_data[index+4] << 8 | m_data[index+5];
                a = m_data[index+6] << 8 | m_data[index+7];
            }
            return Pixel(r,g,b,a);
        }
    }


    // Simply a different way of calling opIndex
    Pixel getPixel(size_t x, size_t y, bool scaleToByte = true)
    {
        return this[x,y,scaleToByte];
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
    Img!F copy() const
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

        // If old dimensions are 1x1, and algo is BILINEAR, switch to NEAREST
        if ((m_width == 1 || m_height == 1) && algo == ResizeAlgo.BILINEAR)
        {
            algo = ResizeAlgo.NEAREST;
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

    /**
    * Write this image to disk with the given filename. Format can be inferred from
    * filename extension by default, or supplied explicitly.
    */
    bool write(string filename, ImageFormat fmt = ImageFormat.GETFROMEXTENSION)
    {
        Encoder enc;
        if (fmt == ImageFormat.GETFROMEXTENSION)
        {
            enc = getEncoder(filename);
        }
        else if (fmt == ImageFormat.PNG)
        {
            enc = new PngEncoder();
        }

        if (enc is null)
            return false;
        else
            return enc.write(this, filename);
    }


    // Getters
    @property const(uint) width() const { return m_width; } // ditto
    @property const(uint) height() const { return m_height; } // ditto
    @property const(int) stride() const { return m_stride; } // ditto
    @property const(uint) bitDepth() const { return m_bitDepth; } // ditto
    @property const(Px) pixelFormat() const { return F; } // ditto
    @property const(ubyte[]) pixels() const { return m_data; } // ditto
    @property ref ubyte[] pixels() { return m_data; } // ditto
    @property ubyte* pixelsPtr() { return m_data.ptr; } // ditto


private:

    // Get the byte index and bit offset for a given (x,y)
    uint getIndex(size_t x, size_t y)
    {
        return cast(uint)(x + y*m_width)*m_stride;
    }


    // Cropping algorithm - If (x,y) is in the original, return that pixel, else return 0,0,0,0
    ushort[4] getCropped(Img!F i, float x, float y, uint col, uint row)
    {
        Pixel p;
        if (col < i.width && row < i.height)
        {
            p = i[col, row, false];
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
        Pixel p = i[x0, y0, false];
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
        Pixel p1 = i[x0, y0, false];
        Pixel p2 = i[x0+1, y0, false];
        Pixel p3 = i[x0, y0+1, false];
        Pixel p4 = i[x0+1, y0+1, false];

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

