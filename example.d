
import std.bitmanip;
import std.stdio;
import std.container;
import std.string;
import std.conv;
import std.file;
import std.math;
import std.traits;
import std.datetime;
import std.range;

import jpeg;
import sd = simpledisplay;

int main()
{

    string filename = "testimages/lion.jpg";
    Jpeg pic = new Jpeg(filename);

    pic.RGB.resize(pic.RGB.width/2, pic.RGB.height/2);

    sd.SimpleWindow wnd = new sd.SimpleWindow(pic.RGB.width, pic.RGB.height);
    auto sd_image = new sd.Image(pic.RGB.width, pic.RGB.height);

    foreach(x; 0..pic.RGB.width) {
        foreach(y; 0..pic.RGB.height) {
            jpeg.Image.Pixel pix = pic.RGB[x,y];
            sd_image.putPixel(x, y, sd.Color(pix.r, pix.g, pix.b));
        }
    }

    wnd.draw().drawImage(sd.Point(0,0), sd_image);
    wnd.eventLoop(0, (int) { wnd.close(); });

    return 0;
}
