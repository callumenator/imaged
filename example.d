
module example;

import std.stdio;

import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{

    string filename = "testimages/earth.png";
    //Jpeg pic = new Jpeg(filename);
    Png pic = new Png(filename);


    //pic.RGB.resize(pic.RGB.width/2, pic.RGB.height/2);

    /// Make a window and simpledisplay image
    sd.SimpleWindow wnd = new sd.SimpleWindow(pic.RGB.width, pic.RGB.height);
    auto sd_image = new sd.Image(pic.RGB.width, pic.RGB.height);

    /// Fill the simpledisplay image with pic colors
    foreach(x; 0..pic.RGB.width) {
        foreach(y; 0..pic.RGB.height) {
            jpeg.Image.Pixel pix = pic.RGB[x,y];
            sd_image.putPixel(x, y, sd.Color(pix.r, pix.g, pix.b));
        }
    }

    /// Show the image in the window
    wnd.draw().drawImage(sd.Point(0,0), sd_image);
    wnd.eventLoop(0, (int) { wnd.close(); });


    return 1;
}
