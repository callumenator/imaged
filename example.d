
module example;

import std.stdio,
std.datetime,
std.file,
std.stream;

import image;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{

    /**
    * For simple usage, loading from a file can be achieved by:
    * Image pic = load(string filename);
    */

    /**
    * The example below shows how to decode using a stream.
    * Note that it is quite slow, since we resize and re-paint
    * the image after every streamParse. This is just designed
    * to show usage, it is not efficient.
    */

    // Grab a directory listing
    auto dFiles = dirEntries("testimages/","*.png",SpanMode.shallow);


    Image img = load(dFiles.front.name, true);
    img.write("c:/cal/testimage.png");


    IMGError err;
    Image pic = load("c:/cal/testimage.png", true, err);
    writeln(err.message);
    pic.resize(512, 512, Image.ResizeAlgo.NEAREST);

    // Make a window and simpledisplay image, with fixed width to keep things simple
    sd.SimpleWindow wnd = new sd.SimpleWindow(512, 512, "Press any key to change image, ESC to close");
    auto sd_image = new sd.Image(512, 512);

            foreach(x; 0..512)
            {
                foreach(y; 0..512)
                {

                    // get the pixel at location (x,y)
                    Pixel pix = pic[x,y];

                    // Use the alpha channel (if any) to blend the image to a white background
                    int r = cast(int)((pix.a/255.)*pix.r + (1 - pix.a/255.)*255);
                    int g = cast(int)((pix.a/255.)*pix.g + (1 - pix.a/255.)*255);
                    int b = cast(int)((pix.a/255.)*pix.b + (1 - pix.a/255.)*255);

                    // Paint in the pixel in simpledisplay image
                    sd_image.putPixel(x, y, sd.Color(r, g, b));
                }
            }
            // Draw the current image
            wnd.draw().drawImage(sd.Point(0,0), sd_image);


    return 0;


    // This is the simpledisplay event loop
    wnd.eventLoop(0,

        // Character presses are handled here
        (dchar c)
        {

        // Output the filename we are loading
        writeln(dFiles.front.name);

        // Get a decoder for this file
        Decoder dcd = getDecoder(dFiles.front.name);

        // Create a stream around the file
        Stream stream = new BufferedFile(dFiles.front.name);

        // Parse the stream until empty
        while(dcd.parseStream(stream))
        {
            // Get a handle to the image being created by the decoder
            auto orig_pic = dcd.image;
            if (orig_pic is null) continue;

            // Make a copy so we can resize to fit the window
            auto pic = orig_pic.copy();

            // Resize using nearest neighbour (alternatives are CROP and BILINEAR)
            pic.resize(512, 512, Image.ResizeAlgo.NEAREST);

            /*
            * Paint to the simpledisplay image, using the resized copy of the decoded
            * part of the current image
            */
            foreach(x; 0..512)
            {
                foreach(y; 0..512)
                {

                    // get the pixel at location (x,y)
                    Pixel pix = pic[x,y];

                    // Use the alpha channel (if any) to blend the image to a white background
                    int r = cast(int)((pix.a/255.)*pix.r + (1 - pix.a/255.)*255);
                    int g = cast(int)((pix.a/255.)*pix.g + (1 - pix.a/255.)*255);
                    int b = cast(int)((pix.a/255.)*pix.b + (1 - pix.a/255.)*255);

                    // Paint in the pixel in simpledisplay image
                    sd_image.putPixel(x, y, sd.Color(r, g, b));
                }
            }
            // Draw the current image
            wnd.draw().drawImage(sd.Point(0,0), sd_image);
        }
        // Move on to the next filename
        dFiles.popFront();

        },

        // Key presses are handled here
        (int key)
        {
            writeln("Got a keydown event: ", key);
            if(key == sd.KEY_ESCAPE)
            {
                wnd.close();
            }
        });

    return 0;
}
