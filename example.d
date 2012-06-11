
module example;

import std.stdio, std.datetime;

import image;
import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{

    string filename = "testimages/clouds.jpeg";
    //Png pic = new Png(filename);
    Jpeg pic = new Jpeg(filename);

    //pic.image.resize(pic.image.width/2, pic.image.height/2);

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
