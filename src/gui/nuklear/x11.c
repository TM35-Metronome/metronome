#define NK_XLIB_IMPLEMENTATION
#include "x11.h"

Window defaultRootWindow(Display *display) {
    return DefaultRootWindow(display);
}

void nkXlibRender(Drawable screen, const struct nk_color *clear) {
    nk_xlib_render(screen, *clear);
}
