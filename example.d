
module example;

import std.stdio, std.datetime;

import image;
import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{

    string filename = "testimages/clouds.jpeg";

    Jpeg pic;
    StopWatch sw;
    sw.start();

    int count = 1;
    foreach(i; 0..count) {
        long t = sw.peek().msecs;
        pic = new Jpeg(filename, false, true, Jpeg.Upsampling.BILINEAR);
        writeln(i, ", ", sw.peek().msecs - t);
    }

    sw.stop();
    writeln();
    writeln(sw.peek().msecs/cast(float)count);
    //Png pic = new Png(filename);

    pic.image.resize(pic.image.width, pic.image.height);

    /// Make a window and simpledisplay image
    sd.SimpleWindow wnd = new sd.SimpleWindow(pic.image.width, pic.image.height);
    auto sd_image = new sd.Image(pic.image.width, pic.image.height);

    /// Fill the simpledisplay image with pic colors

    foreach(x; 0..pic.image.width) {
        foreach(y; 0..pic.image.height) {
            Pixel pix = pic.image[x,y];
            sd_image.putPixel(x, y, sd.Color(pix.r, pix.g, pix.b));
        }
    }


    /// Show the image in the window
    wnd.draw().drawImage(sd.Point(0,0), sd_image);
    wnd.eventLoop(0, (int) { wnd.close(); });


    return 1;
}
