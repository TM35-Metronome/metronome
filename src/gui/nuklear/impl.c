#define NK_IMPLEMENTATION
#include "impl.h"

int nkBegin(struct nk_context *ctx, const char *title, const struct nk_rect *bounds, nk_flags flags) {
    return nk_begin(ctx, title, *bounds, flags);
}

int nkComboBeginText(struct nk_context *ctx, const char *selected, int len, const struct nk_vec2 *size) {
    return nk_combo_begin_text(ctx, selected, len, *size);
}

void nkWindowGetContentRegion(struct nk_context *ctx, struct nk_rect *res) {
    *res = nk_window_get_content_region(ctx);
}

void nkWidgetBounds(struct nk_context *ctx, struct nk_rect *res) {
    *res = nk_widget_bounds(ctx);
}

void nkLayoutWidgetBounds(struct nk_context *ctx, struct nk_rect *res) {
    *res = nk_layout_widget_bounds(ctx);
}

int nkInputHasMouseClickInRect(const struct nk_input *input, enum nk_buttons buttons, const struct nk_rect *rect) {
    return nk_input_has_mouse_click_in_rect(input, buttons, *rect);
}

int nkInputIsMouseClickInRect(const struct nk_input *input, enum nk_buttons buttons, const struct nk_rect *rect) {
    return nk_input_is_mouse_click_in_rect(input, buttons, *rect);
}

int nkInputIsMouseHoveringRect(const struct nk_input *input, const struct nk_rect *rect) {
    return nk_input_is_mouse_hovering_rect(input, *rect);
}

int nkPopupBegin(struct nk_context *ctx, enum nk_popup_type type, const char *title, nk_flags flags, const struct nk_rect *rect) {
    return nk_popup_begin(ctx, type, title, flags, *rect);
}

int nkMenuBeginLabel(struct nk_context *ctx, const char *text, nk_flags align, const struct nk_vec2 *size) {
    return nk_menu_begin_label(ctx, text, align, *size);
}

void nkLayoutSpacePush(struct nk_context *ctx, const struct nk_rect *rect) {
    nk_layout_space_push(ctx, *rect);
}
