#define NK_GDI_IMPLEMENTATION
#include "gdi.h"

size_t width;
size_t height;
GdiFont* font;
WNDCLASSW wc;
ATOM atom;
HWND wnd;
HDC dc;
int running = 1;
int needs_refresh = 1;

static LRESULT CALLBACK WindowProc(HWND wnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    switch (msg) {
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    case WM_SIZE:
        width = LOWORD(lparam);
        height = HIWORD(lparam);
        break;
    }

    if (nk_gdi_handle_event(wnd, msg, wparam, lparam))
        return 0;

    return DefWindowProcW(wnd, msg, wparam, lparam);
}

struct nk_context *nkInit(size_t w, size_t h) {
    RECT rect = { 0, 0, w, h };
    DWORD style = WS_OVERLAPPEDWINDOW;
    DWORD exstyle = WS_EX_APPWINDOW;

    /* Win32 */
    memset(&wc, 0, sizeof(wc));
    wc.style = CS_DBLCLKS;
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = GetModuleHandleW(0);
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"NuklearWindowClass";
    atom = RegisterClassW(&wc);

    AdjustWindowRectEx(&rect, style, FALSE, exstyle);
    wnd = CreateWindowExW(exstyle, wc.lpszClassName, L"Nuklear Demo",
        style | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
        rect.right - rect.left, rect.bottom - rect.top,
        NULL, NULL, wc.hInstance, NULL);
    dc = GetDC(wnd);

    /* GUI */
    font = nk_gdifont_create("Arial", 14);
    width = w;
    height = h;
    return nk_gdi_init(font, dc, w, h);
}

int nkInput(struct nk_context *ctx) {
    MSG msg;
    int res = 1;
    nk_input_begin(ctx);
    if (needs_refresh == 0) {
        if (GetMessageW(&msg, NULL, 0, 0) <= 0)
            res = 0;
        else {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        needs_refresh = 1;
    } else needs_refresh = 0;

    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT)
            res = 0;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
        needs_refresh = 1;
    }
    nk_input_end(ctx);
    return res;
}

void nkRender(struct nk_context *ctx) {
    nk_gdi_render(nk_rgb(0,0,0));
}

void nkDeinit(struct nk_context *ctx) {
    nk_gdifont_del(font);
    ReleaseDC(wnd, dc);
    UnregisterClassW(wc.lpszClassName, wc.hInstance);
}
