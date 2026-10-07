// Input for the end-to-end tests (tests/e2e/run.sh): a virtual pointer and a
// virtual keyboard on the nested compositor, driven by argv. Built by run.sh
// into its work directory and only ever pointed at the nested socket.
//   vinput extent W H | move X Y | click [right] | down | up | wheel N
//          | key [super|shift|ctrl|alt...] CODE | type TEXT | sleep MS
// CODE is a Linux key code (KEY_Y = 21); X and Y are layout coordinates
// within the extent (the whole layout by default, 4480x1440).
#define _GNU_SOURCE
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "virtual-keyboard-unstable-v1-client.h"
#include "wlr-virtual-pointer-unstable-v1-client.h"

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *pm;
static struct zwp_virtual_keyboard_manager_v1 *km;

static void global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
    (void)data;
    if (strcmp(iface, wl_seat_interface.name) == 0)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    else if (strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
        pm = wl_registry_bind(r, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
    else if (strcmp(iface, zwp_virtual_keyboard_manager_v1_interface.name) == 0)
        km = wl_registry_bind(r, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    (void)version;
}

static void global_remove(void *data, struct wl_registry *r, uint32_t name) {
    (void)data; (void)r; (void)name;
}

static const struct wl_registry_listener reg_listener = { global, global_remove };

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void pause_ms(struct wl_display *d, int ms) {
    wl_display_roundtrip(d);
    usleep((useconds_t)ms * 1000);
}

static uint32_t mask_of(struct xkb_keymap *km_, const char *mod) {
    xkb_mod_index_t i = xkb_keymap_mod_get_index(km_, mod);
    return i == XKB_MOD_INVALID ? 0 : (1u << i);
}

static int code_for_char(char c, int *shift) {
    static const char *row1 = "1234567890";
    static const int row1c[] = { KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0 };
    static const char *letters = "abcdefghijklmnopqrstuvwxyz";
    static const int letterc[] = { KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K,
                                   KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V,
                                   KEY_W, KEY_X, KEY_Y, KEY_Z };
    *shift = 0;
    if (c >= 'A' && c <= 'Z') {
        *shift = 1;
        c = (char)(c - 'A' + 'a');
    }
    const char *p = strchr(letters, c);
    if (p && c)
        return letterc[p - letters];
    p = strchr(row1, c);
    if (p && c)
        return row1c[p - row1];
    switch (c) {
    case ' ': return KEY_SPACE;
    case '-': return KEY_MINUS;
    case '.': return KEY_DOT;
    case '/': return KEY_SLASH;
    case '<': *shift = 1; return KEY_COMMA;
    case '>': *shift = 1; return KEY_DOT;
    case '"': *shift = 1; return KEY_APOSTROPHE;
    case '=': return KEY_EQUAL;
    }
    return -1;
}

int main(int argc, char **argv) {
    struct wl_display *d = wl_display_connect(NULL);
    if (!d) {
        fprintf(stderr, "vinput: no wayland display\n");
        return 1;
    }
    struct wl_registry *r = wl_display_get_registry(d);
    wl_registry_add_listener(r, &reg_listener, NULL);
    wl_display_roundtrip(d);
    if (!seat || !pm || !km) {
        fprintf(stderr, "vinput: missing seat=%p pointer=%p keyboard=%p\n", (void *)seat, (void *)pm, (void *)km);
        return 1;
    }
    struct zwlr_virtual_pointer_v1 *ptr = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pm, seat);
    struct zwp_virtual_keyboard_v1 *kb = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(km, seat);

    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = { .rules = NULL, .model = "pc105", .layout = "us", .variant = NULL, .options = NULL };
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("vinput-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t)size) {
        fprintf(stderr, "vinput: keymap\n");
        return 1;
    }
    zwp_virtual_keyboard_v1_keymap(kb, XKB_KEYMAP_FORMAT_TEXT_V1, fd, (uint32_t)size);
    uint32_t m_shift = mask_of(keymap, XKB_MOD_NAME_SHIFT), m_ctrl = mask_of(keymap, XKB_MOD_NAME_CTRL),
             m_alt = mask_of(keymap, XKB_MOD_NAME_ALT), m_super = mask_of(keymap, XKB_MOD_NAME_LOGO);
    pause_ms(d, 50);

    uint32_t ext_w = 4480, ext_h = 1440;
    for (int i = 1; i < argc; i++) {
        const char *cmd = argv[i];
        if (strcmp(cmd, "extent") == 0 && i + 2 < argc) {
            ext_w = (uint32_t)atoi(argv[++i]);
            ext_h = (uint32_t)atoi(argv[++i]);
        } else if (strcmp(cmd, "move") == 0 && i + 2 < argc) {
            uint32_t x = (uint32_t)atoi(argv[++i]), y = (uint32_t)atoi(argv[++i]);
            zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), x, y, ext_w, ext_h);
            zwlr_virtual_pointer_v1_frame(ptr);
            pause_ms(d, 30);
        } else if (strcmp(cmd, "click") == 0) {
            uint32_t btn = BTN_LEFT;
            if (i + 1 < argc && strcmp(argv[i + 1], "right") == 0) {
                btn = BTN_RIGHT;
                i++;
            }
            zwlr_virtual_pointer_v1_button(ptr, now_ms(), btn, WL_POINTER_BUTTON_STATE_PRESSED);
            zwlr_virtual_pointer_v1_frame(ptr);
            pause_ms(d, 40);
            zwlr_virtual_pointer_v1_button(ptr, now_ms(), btn, WL_POINTER_BUTTON_STATE_RELEASED);
            zwlr_virtual_pointer_v1_frame(ptr);
            pause_ms(d, 30);
        } else if (strcmp(cmd, "down") == 0 || strcmp(cmd, "up") == 0) {
            zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT,
                strcmp(cmd, "down") == 0 ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
            zwlr_virtual_pointer_v1_frame(ptr);
            pause_ms(d, 40);
        } else if (strcmp(cmd, "wheel") == 0 && i + 1 < argc) {
            int n = atoi(argv[++i]);
            zwlr_virtual_pointer_v1_axis(ptr, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(15 * n));
            zwlr_virtual_pointer_v1_frame(ptr);
            pause_ms(d, 30);
        } else if (strcmp(cmd, "key") == 0) {
            uint32_t mods = 0;
            int held[4], nheld = 0;
            while (i + 1 < argc) {
                const char *a = argv[i + 1];
                if (strcmp(a, "super") == 0) { mods |= m_super; held[nheld++] = KEY_LEFTMETA; }
                else if (strcmp(a, "shift") == 0) { mods |= m_shift; held[nheld++] = KEY_LEFTSHIFT; }
                else if (strcmp(a, "ctrl") == 0) { mods |= m_ctrl; held[nheld++] = KEY_LEFTCTRL; }
                else if (strcmp(a, "alt") == 0) { mods |= m_alt; held[nheld++] = KEY_LEFTALT; }
                else break;
                i++;
            }
            if (i + 1 >= argc)
                break;
            int code = atoi(argv[++i]);
            for (int k = 0; k < nheld; k++)
                zwp_virtual_keyboard_v1_key(kb, now_ms(), (uint32_t)held[k], WL_KEYBOARD_KEY_STATE_PRESSED);
            zwp_virtual_keyboard_v1_modifiers(kb, mods, 0, 0, 0);
            pause_ms(d, 20);
            zwp_virtual_keyboard_v1_key(kb, now_ms(), (uint32_t)code, WL_KEYBOARD_KEY_STATE_PRESSED);
            pause_ms(d, 30);
            zwp_virtual_keyboard_v1_key(kb, now_ms(), (uint32_t)code, WL_KEYBOARD_KEY_STATE_RELEASED);
            pause_ms(d, 20);
            for (int k = nheld - 1; k >= 0; k--)
                zwp_virtual_keyboard_v1_key(kb, now_ms(), (uint32_t)held[k], WL_KEYBOARD_KEY_STATE_RELEASED);
            zwp_virtual_keyboard_v1_modifiers(kb, 0, 0, 0, 0);
            pause_ms(d, 30);
        } else if (strcmp(cmd, "type") == 0 && i + 1 < argc) {
            const char *s = argv[++i];
            for (; *s; s++) {
                int shift = 0, code = code_for_char(*s, &shift);
                if (code < 0)
                    continue;
                if (shift) {
                    zwp_virtual_keyboard_v1_key(kb, now_ms(), KEY_LEFTSHIFT, WL_KEYBOARD_KEY_STATE_PRESSED);
                    zwp_virtual_keyboard_v1_modifiers(kb, m_shift, 0, 0, 0);
                }
                zwp_virtual_keyboard_v1_key(kb, now_ms(), (uint32_t)code, WL_KEYBOARD_KEY_STATE_PRESSED);
                zwp_virtual_keyboard_v1_key(kb, now_ms(), (uint32_t)code, WL_KEYBOARD_KEY_STATE_RELEASED);
                if (shift) {
                    zwp_virtual_keyboard_v1_key(kb, now_ms(), KEY_LEFTSHIFT, WL_KEYBOARD_KEY_STATE_RELEASED);
                    zwp_virtual_keyboard_v1_modifiers(kb, 0, 0, 0, 0);
                }
                pause_ms(d, 8);
            }
        } else if (strcmp(cmd, "sleep") == 0 && i + 1 < argc) {
            pause_ms(d, atoi(argv[++i]));
        } else {
            fprintf(stderr, "vinput: unknown or incomplete command %s\n", cmd);
            return 2;
        }
    }
    wl_display_roundtrip(d);
    zwp_virtual_keyboard_v1_destroy(kb);
    zwlr_virtual_pointer_v1_destroy(ptr);
    wl_display_roundtrip(d);
    wl_display_disconnect(d);
    return 0;
}
