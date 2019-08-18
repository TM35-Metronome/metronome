#define NK_IMPLEMENTATION
#include "impl.h"

int nkBegin(struct nk_context *ctx, const char *title, const struct nk_rect *bounds, nk_flags flags) {
    return nk_begin(ctx, title, *bounds, flags);
}

int nkPopupBegin(struct nk_context *ctx, enum nk_popup_type type, const char *title, nk_flags flags, const struct nk_rect *rect) {
    return nk_popup_begin(ctx, type, title, flags, *rect);
}

int nkMenuBeginLabel(struct nk_context *ctx, const char *text, nk_flags align, const struct nk_vec2 *size) {
    return nk_menu_begin_label(ctx, text, align, *size);
}
