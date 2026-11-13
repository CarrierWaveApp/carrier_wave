#include "spots_window.h"

#include <pebble.h>

#include "comm.h"

#define CW_MAX_SPOTS 20
#define CW_TITLE_LEN 24
#define CW_SUBTITLE_LEN 32

typedef struct {
  char title[CW_TITLE_LEN];
  char subtitle[CW_SUBTITLE_LEN];
} cw_spot_row_t;

static Window *s_window = NULL;
static MenuLayer *s_menu = NULL;
static TextLayer *s_status = NULL;
static cw_spot_row_t s_rows[CW_MAX_SPOTS];
static uint16_t s_row_count = 0;

static uint16_t menu_num_rows(MenuLayer *menu, uint16_t section,
                              void *context) {
  (void)menu;
  (void)section;
  (void)context;
  return s_row_count == 0 ? 1 : s_row_count;
}

static void menu_draw_row(GContext *ctx, const Layer *cell, MenuIndex *idx,
                          void *context) {
  (void)context;
  if (s_row_count == 0) {
    menu_cell_basic_draw(ctx, cell, "No spots", "Pull down to refresh", NULL);
    return;
  }
  cw_spot_row_t *row = &s_rows[idx->row];
  menu_cell_basic_draw(ctx, cell, row->title, row->subtitle, NULL);
}

static int16_t menu_cell_height(MenuLayer *menu, MenuIndex *idx,
                                void *context) {
  (void)menu;
  (void)idx;
  (void)context;
  return 44;
}

static void menu_select(MenuLayer *menu, MenuIndex *idx, void *context) {
  (void)menu;
  (void)idx;
  (void)context;
  // Tap = re-fetch.
  s_row_count = 0;
  text_layer_set_text(s_status, "Refreshing...");
  layer_set_hidden(text_layer_get_layer(s_status), false);
  menu_layer_reload_data(s_menu);
  cw_comm_send_action(CW_ACTION_FETCH_SPOTS);
}

static void inbox_handler(DictionaryIterator *iter) {
  Tuple *count_t = dict_find(iter, MESSAGE_KEY_SPOT_COUNT);
  Tuple *index_t = dict_find(iter, MESSAGE_KEY_SPOT_INDEX);
  Tuple *call_t = dict_find(iter, MESSAGE_KEY_SPOT_CALLSIGN);
  Tuple *freq_t = dict_find(iter, MESSAGE_KEY_SPOT_FREQ_MHZ);
  Tuple *mode_t = dict_find(iter, MESSAGE_KEY_SPOT_MODE);
  Tuple *band_t = dict_find(iter, MESSAGE_KEY_SPOT_BAND);
  Tuple *ref_t = dict_find(iter, MESSAGE_KEY_SPOT_PARK_REF);

  if (count_t && count_t->type == TUPLE_INT) {
    s_row_count = 0;
    layer_set_hidden(text_layer_get_layer(s_status), true);
    menu_layer_reload_data(s_menu);
    return;
  }

  if (index_t && call_t) {
    int idx = index_t->value->int32;
    if (idx < 0 || idx >= CW_MAX_SPOTS) {
      return;
    }
    cw_spot_row_t *row = &s_rows[idx];
    snprintf(row->title, CW_TITLE_LEN, "%s",
             call_t->type == TUPLE_CSTRING ? call_t->value->cstring : "?");
    const char *freq =
        freq_t && freq_t->type == TUPLE_CSTRING ? freq_t->value->cstring : "";
    const char *mode =
        mode_t && mode_t->type == TUPLE_CSTRING ? mode_t->value->cstring : "";
    const char *band =
        band_t && band_t->type == TUPLE_CSTRING ? band_t->value->cstring : "";
    const char *ref =
        ref_t && ref_t->type == TUPLE_CSTRING ? ref_t->value->cstring : "";
    if (ref[0]) {
      snprintf(row->subtitle, CW_SUBTITLE_LEN, "%s %s %s %s", band, freq, mode,
               ref);
    } else {
      snprintf(row->subtitle, CW_SUBTITLE_LEN, "%s %s %s", band, freq, mode);
    }
    if (idx >= s_row_count) {
      s_row_count = idx + 1;
    }
    menu_layer_reload_data(s_menu);
  }
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_menu = menu_layer_create(bounds);
  menu_layer_set_callbacks(s_menu, NULL,
                           (MenuLayerCallbacks){
                               .get_num_rows = menu_num_rows,
                               .draw_row = menu_draw_row,
                               .get_cell_height = menu_cell_height,
                               .select_click = menu_select,
                           });
  menu_layer_set_click_config_onto_window(s_menu, window);
  layer_add_child(root, menu_layer_get_layer(s_menu));

  s_status = text_layer_create(GRect(0, bounds.size.h - 18, bounds.size.w, 16));
  text_layer_set_text(s_status, "Loading spots...");
  text_layer_set_font(s_status, fonts_get_system_font(FONT_KEY_GOTHIC_14));
  text_layer_set_text_alignment(s_status, GTextAlignmentCenter);
  text_layer_set_background_color(s_status, GColorClear);
  layer_add_child(root, text_layer_get_layer(s_status));

  s_row_count = 0;
  cw_comm_set_inbox_handler(inbox_handler);
  cw_comm_send_action(CW_ACTION_FETCH_SPOTS);
}

static void window_unload(Window *window) {
  (void)window;
  cw_comm_set_inbox_handler(NULL);
  if (s_menu) {
    menu_layer_destroy(s_menu);
    s_menu = NULL;
  }
  if (s_status) {
    text_layer_destroy(s_status);
    s_status = NULL;
  }
}

void cw_spots_window_push(void) {
  if (!s_window) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
                                             .load = window_load,
                                             .unload = window_unload,
                                         });
  }
  window_stack_push(s_window, true);
}
