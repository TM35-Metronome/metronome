#include <stddef.h>
#include <stdint.h>

void zig_assert(int ok);
void* zig_memcopy(void *dst, const void *src, size_t n);
void zig_memset(void *ptr, uint8_t c0, size_t size);
float zig_sqrt(float x);
float zig_sin(float x);
float zig_cos(float x);

#define NK_ASSERT zig_assert
#define NK_MEMSET zig_memset
#define NK_MEMCPY zig_memcopy
#define NK_SQRT zig_sqrt
#define NK_SIN zig_sin
#define NK_COS zig_cos
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_FIXED_TYPES
#include <nuklear.h>

int nkBegin(struct nk_context *ctx, const char *title, const struct nk_rect *bounds, nk_flags flags);
int nkComboBeginText(struct nk_context *ctx, const char *selected, int len, const struct nk_vec2 *size);
void nkWindowGetContentRegion(struct nk_context *ctx, struct nk_rect *res);
void nkWidgetBounds(struct nk_context *ctx, struct nk_rect *res);
void nkLayoutWidgetBounds(struct nk_context *ctx, struct nk_rect *res);
int nkInputHasMouseClickInRect(const struct nk_input *input, enum nk_buttons buttons, const struct nk_rect *rect);
int nkInputIsMouseClickInRect(const struct nk_input *input, enum nk_buttons buttons, const struct nk_rect *rect);
int nkInputIsMouseHoveringRect(const struct nk_input *input, const struct nk_rect *rect);
int nkPopupBegin(struct nk_context *ctx, enum nk_popup_type type, const char *title, nk_flags flags, const struct nk_rect *rect);
int nkMenuBeginLabel(struct nk_context *ctx, const char *text, nk_flags align, const struct nk_vec2 *size);
void nkLayoutSpacePush(struct nk_context *ctx, const struct nk_rect *rect);

extern size_t width;
extern size_t height;

struct nk_context *nkInit(size_t w, size_t h);
int nkInput(struct nk_context *ctx);
void nkRender(struct nk_context *ctx);
void nkDeinit(struct nk_context *ctx);
