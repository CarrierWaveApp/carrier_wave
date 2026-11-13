#include "menu_window.h"

#include <pebble.h>

#include "memories_window.h"
#include "session_window.h"
#include "solar_window.h"
#include "spots_window.h"
#include "utc_window.h"

#define CW_MENU_ROWS 5

static Window *s_window = NULL;
static SimpleMenuLayer *s_menu = NULL;
static SimpleMenuSection s_sections[1];
static SimpleMenuItem s_items[CW_MENU_ROWS];

static void on_solar(int index, void *ctx) {
  (void)index;
  (void)ctx;
  cw_solar_window_push();
}

static void on_spots(int index, void *ctx) {
  (void)index;
  (void)ctx;
  cw_spots_window_push();
}

static void on_utc(int index, void *ctx) {
  (void)index;
  (void)ctx;
  cw_utc_window_push();
}

static void on_session(int index, void *ctx) {
  (void)index;
  (void)ctx;
  cw_session_window_push();
}

static void on_memories(int index, void *ctx) {
  (void)index;
  (void)ctx;
  cw_memories_window_push();
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_items[0] = (SimpleMenuItem){
      .title = "Solar", .subtitle = "K, A, SFI", .callback = on_solar};
  s_items[1] = (SimpleMenuItem){
      .title = "Spots", .subtitle = "POTA activators", .callback = on_spots};
  s_items[2] = (SimpleMenuItem){
      .title = "UTC", .subtitle = "Zulu clock", .callback = on_utc};
  s_items[3] = (SimpleMenuItem){.title = "Session",
                                .subtitle = "Active log",
                                .callback = on_session};
  s_items[4] = (SimpleMenuItem){.title = "CW Messages",
                                .subtitle = "Key memories",
                                .callback = on_memories};

  s_sections[0] =
      (SimpleMenuSection){.num_items = CW_MENU_ROWS, .items = s_items};

  s_menu = simple_menu_layer_create(bounds, window, s_sections, 1, NULL);
  layer_add_child(root, simple_menu_layer_get_layer(s_menu));
}

static void window_unload(Window *window) {
  (void)window;
  if (s_menu) {
    simple_menu_layer_destroy(s_menu);
    s_menu = NULL;
  }
}

void cw_menu_window_push(void) {
  if (!s_window) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
                                             .load = window_load,
                                             .unload = window_unload,
                                         });
  }
  window_stack_push(s_window, true);
}
