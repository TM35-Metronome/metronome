#define NK_XLIB_USE_XFT
#include "impl.h"
#include <nuklear_xlib.h>

Window defaultRootWindow(Display *display);
void nkXlibRender(Drawable screen, const struct nk_color *clear);