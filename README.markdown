# Routines for loading/decoding and writing/encoding images. 

Implemented decoders:
- JPEG: baseline 8-bit (Huffman sequential DCT with 8-bits per channel).
- PNG: loads all images in the PNG test suite. 

Usage - loading from a file:
```
Image img = load("imagepath/imagefile.png");
```

Usage - loading from a stream:
```
Stream dataStream;
Decoder dcoder = getDecoder("imagepath/imagefile.png");
while(dcoder.parseStream(dataStream))
{
  do stuff, like draw the current interlaced png, fill the stream, etc.
} 
```

Implemented encoders:
- PNG: will write out PNG files from 8-bit versions of Image class. Uses adaptive filtering, 
output PNG's are non-interlaced and only contain critical chunks.

Usage - writing out a PNG:
```
ubyte[] data = myImageData;  // note that it must be pixel interleaved for RGB/RGBA to work
Image myImg = new Img!(Px.R8G8B8)(width, height, data);
myImg.write("path/to/output.png");
```

Images:
- the Image class can be used to hold various pixel formats. It also has routines for resizing, e.g.:

``` 
Image myImg; 
myImg.resize(newWidth, newHeight, Image.ResizeAlgo.BILINEAR);
```

- Resizing can be done by cropping (```Image.ResizeAlgo.CROP```), nearest neighbour
(```Image.ResizeAlgo.NEAREST```) or bilinear filtering (```Image.ResizeAlgo.BILINEAR```).


simpledisplay.d is from Adam Ruppe's repo: misc-stuff-including-D-programming-language-web-stuff.

Some details:
- JPEG: the decoder uses Nearest Neighbour upsampling of the chroma components by default, but 
bilinear upsampling is also available. The decoder only retains enough info for one MCU at a 
time, so it decodes on the fly. Not thoroughly tested, particularly not on greyscale images, 
so these might not work.

- PNG: better tested thanks to the PNG test suite. Handles all bit depths, but note that 
sub-byte packing (like 1, 2, 4 bits per pixel) are unpacked when stored in the Image class. This 
makes them _much_ easier to deal with later, at the expense of increasing their memory footprint. 
16 bit resolution is retained, but by default, when reading pixels out of a 16-bit Image, they are 
downshifted to 8-bit precision, since usually that is what you want. Decoder retains two scanlines 
of info, so it decodes on the fly and can be used with interlaced PNG's to give a progressive display. 
Note that this makes it slightly less efficient than it could be. It only decodes critical chunks. 
Ancillary chunks are easy enough to add though. 
