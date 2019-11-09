#define NK_XLIB_IMPLEMENTATION
#include "x11.h"

size_t width;
size_t height;

struct XWindow {
    Display *dpy;
    Window root;
    Visual *vis;
    Colormap cmap;
    XWindowAttributes attr;
    XSetWindowAttributes swa;
    Window win;
    int screen;
    XFont *font;
    unsigned int width;
    unsigned int height;
    Atom wm_delete_window;
} xw;

struct nk_context *nkInit(size_t w, size_t h) {

    /* X11 */
    memset(&xw, 0, sizeof xw);
    xw.dpy = XOpenDisplay(NULL);
    if (!xw.dpy)
        return NULL;
    xw.root = DefaultRootWindow(xw.dpy);
    xw.screen = XDefaultScreen(xw.dpy);
    xw.vis = XDefaultVisual(xw.dpy, xw.screen);
    xw.cmap = XCreateColormap(xw.dpy,xw.root,xw.vis,AllocNone);

    xw.swa.colormap = xw.cmap;
    xw.swa.event_mask =
        ExposureMask | KeyPressMask | KeyReleaseMask |
        ButtonPress | ButtonReleaseMask| ButtonMotionMask |
        Button1MotionMask | Button3MotionMask | Button4MotionMask | Button5MotionMask|
        PointerMotionMask | KeymapStateMask;
    xw.win = XCreateWindow(xw.dpy, xw.root, 0, 0, w, h, 0,
        XDefaultDepth(xw.dpy, xw.screen), InputOutput,
        xw.vis, CWEventMask | CWColormap, &xw.swa);

    XStoreName(xw.dpy, xw.win, "X11");
    XMapWindow(xw.dpy, xw.win);
    xw.wm_delete_window = XInternAtom(xw.dpy, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(xw.dpy, xw.win, &xw.wm_delete_window, 1);
    XGetWindowAttributes(xw.dpy, xw.win, &xw.attr);
    xw.width = (unsigned int)xw.attr.width;
    xw.height = (unsigned int)xw.attr.height;
    width = xw.width;
    height = xw.height;

    /* GUI */
    xw.font = nk_xfont_create(xw.dpy, "Arial");
    return nk_xlib_init(xw.font, xw.dpy, xw.screen, xw.win,
#ifdef NK_XLIB_USE_XFT
                    xw.vis, xw.cmap,
#endif
                    xw.width, xw.height);
}

int nkInput(struct nk_context *ctx) {
    XEvent evt;
    nk_input_begin(ctx);
    while (XPending(xw.dpy)) {
        XNextEvent(xw.dpy, &evt);
        if (evt.type == ClientMessage) 
            return 0;
        if (evt.type == ConfigureNotify) {
            width = evt.xconfigure.width;
            height = evt.xconfigure.height;
        }
        if (XFilterEvent(&evt, xw.win)) continue;
        nk_xlib_handle_event(xw.dpy, xw.screen, xw.win, &evt);
    }
    nk_input_end(ctx);
    return 1;
}

void nkRender(struct nk_context *ctx) {
    /* Draw */
    XClearWindow(xw.dpy, xw.win);
    nk_xlib_render(xw.win, nk_rgb(0,0,0));
    XFlush(xw.dpy);
}

void nkDeinit(struct nk_context *ctx) {
    nk_xfont_del(xw.dpy, xw.font);
    nk_xlib_shutdown();
    XUnmapWindow(xw.dpy, xw.win);
    XFreeColormap(xw.dpy, xw.cmap);
    XDestroyWindow(xw.dpy, xw.win);
    XCloseDisplay(xw.dpy);
}