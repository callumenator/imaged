
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
import simpledisplay;

int main()
{
    StopWatch timer;
    string filename = "pier.jpeg";
    //string filename = "philo_sky3_1k.jpg";
    Jpeg pic = new Jpeg(filename);

    /++
    timer.start;
    foreach(i; 0..50) {
        if (i % 2 == 0) {
            pic.RGB.resize(pic.RGB.width/2, pic.RGB.height/2);
        } else {
            pic.RGB.resize(pic.RGB.width*2, pic.RGB.height*2);
        }
        writeln(i);
    }
    timer.stop;
    writeln(timer.peek().msecs/50.0);
    ++/

    pic.RGB.resize(pic.RGB.width/2, pic.RGB.height/2);

    SimpleWindow wnd = new SimpleWindow(pic.RGB.width, pic.RGB.height);
    auto image = new simpledisplay.Image(pic.RGB.width, pic.RGB.height);
    foreach(x; 0..pic.RGB.width) {
        foreach(y; 0..pic.RGB.height) {
            jpeg.Image.Pixel pix = pic.RGB[x,y];
            image.putPixel(x, y, Color(pix.r, pix.g, pix.b));
        }
    }

    wnd.draw().drawImage(Point(0,0), image);
    wnd.eventLoop(0, (int) { wnd.close(); });

    return 0;
}
