
module example;

import std.stdio, std.datetime, std.file;

import image;
import jpeg;
import png;
import sd = simpledisplay; /// Adam Ruppe's simpledisplay.d

int main()
{
    auto dFiles = dirEntries("testimages/","*",SpanMode.depth);

        /// Make a window and simpledisplay image
        sd.SimpleWindow wnd = new sd.SimpleWindow(320, 320);
        auto sd_image = new sd.Image(320, 320);

        wnd.eventLoop(0,
		(dchar c) {

            writeln(dFiles.front.name);
            Image pic = load(dFiles.front.name);
            dFiles.popFront();
            if (pic is null) return;
            pic.resize(320, 320, Image.ResizeAlgo.NEAREST);

			foreach(x; 0..pic.width) {
            foreach(y; 0..pic.height) {
                Pixel pix = pic[x,y];

                int r = pix.r;
                int g = pix.g;
                int b = pix.b;
                int a = pix.a;

                r = cast(int)((a/255.)*r + (1 - a/255.)*255);
                g = cast(int)((a/255.)*g + (1 - a/255.)*255);
                b = cast(int)((a/255.)*b + (1 - a/255.)*255);
                sd_image.putPixel(x, y, sd.Color(r, g, b));
            }
            }
			wnd.image = sd_image;
			wnd.draw().drawImage(sd.Point(0,0), sd_image);
		},
		(int key) {
			writeln("Got a keydown event: ", key);
			if(key == sd.KEY_ESCAPE) {
				wnd.close();
			}
		});


    return 1;
}
