
module example;

import std.stdio, std.datetime;

import image;
import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{
    string filename = "testimages/pngtestsuite/cs5n2c08.png";
    //string filename = "testimages/jupiter.png";
    Image pic = load(filename);

    //pic.resize(pic.width/2, pic.height/2);

    /// Make a window and simpledisplay image
    sd.SimpleWindow wnd = new sd.SimpleWindow(pic.width, pic.height);
    auto sd_image = new sd.Image(pic.width, pic.height);

    /// Fill the simpledisplay image with pic colors

    foreach(x; 0..pic.width) {
        foreach(y; 0..pic.height) {
            Pixel pix = pic[x,y];

            int shft = 0;
            int r = pix.r >> shft;
            int g = pix.g >> shft;
            int b = pix.b >> shft;
            int a = pix.a >> shft;

            r = cast(int)((a/255.)*r + (1 - a/255.)*255);
            g = cast(int)((a/255.)*g + (1 - a/255.)*255);
            b = cast(int)((a/255.)*b + (1 - a/255.)*255);
            sd_image.putPixel(x, y, sd.Color(r, g, b));
        }
    }

    /// Show the image in the window
    wnd.draw().drawImage(sd.Point(0,0), sd_image);
    wnd.eventLoop(0, (int) { wnd.close(); });

    return 1;
}
