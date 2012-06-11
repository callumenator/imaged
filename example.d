
module example;

import std.stdio, std.datetime;

import image;
import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{

    string filename = "testimages/clouds.jpeg";
    Image pic = load(filename);

    pic.resize(pic.width/2, pic.height/2);

    /// Make a window and simpledisplay image
    sd.SimpleWindow wnd = new sd.SimpleWindow(pic.width, pic.height);
    auto sd_image = new sd.Image(pic.width, pic.height);

    /// Fill the simpledisplay image with pic colors

    foreach(x; 0..pic.width) {
        foreach(y; 0..pic.height) {
            Pixel pix = pic[x,y];
            sd_image.putPixel(x, y, sd.Color(pix.r, pix.g, pix.b));
        }
    }

    /// Show the image in the window
    wnd.draw().drawImage(sd.Point(0,0), sd_image);
    wnd.eventLoop(0, (int) { wnd.close(); });

    return 1;
}
