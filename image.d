// Written in the D programming language.

/++
+ Copyright: Copyright 2012 -
+ License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+ Authors: Callum Anderson
+ Date: June 8, 2012
+/
module image;

import std.math;


struct Pixel {
    short r, g, b, a;
}


abstract class Image {

    enum ResizeAlgo {
        CROP,
        NEAREST,
        BILINEAR,
        BICUBIC
    }

    this() {};
    this(uint width, uint height, int nchannels, int bitsPerChannel) {
        m_data = new ubyte[](width*height*nchannels);
        m_width = width;
        m_height = height;
        m_channels = nchannels;
        m_bitsPerChannel = bitsPerChannel;
        m_pixelStride = nchannels*cast(uint)(ceil(bitsPerChannel/8.0f));
    }

    this(uint width, uint height, int nchannels, int bitsPerPixel, ubyte[] data, bool noCopy = false);

    Pixel getPixel(uint x, uint y);

     void resize(uint newWidth, uint newHeight, ResizeAlgo = ResizeAlgo.BILINEAR);

    uint xyToOffset(uint x, uint y) {
        return x + y*m_width*m_pixelStride;
    }

    @property uint width() { return m_width; }
    @property uint height() { return m_height; }
    @property int pixelStride() { return m_pixelStride; }
    @property int bitsPerChannel() { return m_bitsPerChannel; }
    @property ubyte[] pixels() { return m_data; }

private:
    uint m_width, m_height;
    int m_pixelStride;
    int m_channels;
    int m_bitsPerChannel;
    ubyte[] m_data;
}


class ImageRGB8 : Image {

    this(uint width, uint height) {
        super(width, height, 3, 8);
    }

    /++
    this(uint m_width, uint m_height, ubyte[] data) {

    }
    ++/

    Pixel getPixel(uint x, uint y) {
        return Pixel(m_data[xyToOffset(x,y)],
                     m_data[xyToOffset(x,y) + 1],
                     m_data[xyToOffset(x,y) + 2]);
    }

    void resize(uint newWidth, uint newHeight, ResizeAlgo = ResizeAlgo.CROP) {

    }
}
