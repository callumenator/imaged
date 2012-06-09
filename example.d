
module example;

import std.stdio, std.datetime;

import image;
import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{

    string filename = "testimages/pier.jpeg";

    Jpeg pic;

    StopWatch sw;

    sw.start();

    int count = 1;
    foreach(i; 0..count) {
        pic = new Jpeg(filename);
        writeln(i);
    }

    sw.stop();
    writeln();
    writeln(sw.peek().msecs/cast(float)count);
    //Png pic = new Png(filename);


    //pic.RGB.resize(pic.RGB.width/2, pic.RGB.height/2);

    /// Make a window and simpledisplay image
    sd.SimpleWindow wnd = new sd.SimpleWindow(pic.RGB.width, pic.RGB.height);
    auto sd_image = new sd.Image(pic.RGB.width, pic.RGB.height);

    /// Fill the simpledisplay image with pic colors
    foreach(x; 0..pic.RGB.width) {
        foreach(y; 0..pic.RGB.height) {
            Pixel pix = pic.RGB[x,y];
            sd_image.putPixel(x, y, sd.Color(pix.r, pix.g, pix.b));
        }
    }

    /// Show the image in the window
    wnd.draw().drawImage(sd.Point(0,0), sd_image);
    wnd.eventLoop(0, (int) { wnd.close(); });


    return 1;
}
