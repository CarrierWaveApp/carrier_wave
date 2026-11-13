#include "solar_window.h"

#include <pebble.h>

#include "comm.h"

static Window *s_window = NULL;
static TextLayer *s_title = NULL;
static TextLayer *s_kindex = NULL;
static TextLayer *s_aindex = NULL;
static TextLayer *s_sfi = NULL;
static TextLayer *s_propagation = NULL;
static TextLayer *s_status = NULL;

static char s_kindex_buf[32];
static char s_aindex_buf[32];
static char s_sfi_buf[32];
static char s_propagation_buf[32];

static void inbox_handler(DictionaryIterator *iter) {
  Tuple *kt = dict_find(iter, MESSAGE_KEY_K_INDEX);
  Tuple *at = dict_find(iter, MESSAGE_KEY_A_INDEX);
  Tuple *st = dict_find(iter, MESSAGE_KEY_SOLAR_FLUX);
  Tuple *pt = dict_find(iter, MESSAGE_KEY_PROPAGATION);

  if (kt && kt->type == TUPLE_CSTRING) {
    snprintf(s_kindex_buf, sizeof(s_kindex_buf), "K  %s",
             kt->value->cstring);
    text_layer_set_text(s_kindex, s_kindex_buf);
  }
  if (at && at->type == TUPLE_CSTRING) {
    snprintf(s_aindex_buf, sizeof(s_aindex_buf), "A  %s",
             at->value->cstring);
    text_layer_set_text(s_aindex, s_aindex_buf);
  }
  if (st && st->type == TUPLE_CSTRING) {
    snprintf(s_sfi_buf, sizeof(s_sfi_buf), "SFI %s", st->value->cstring);
    text_layer_set_text(s_sfi, s_sfi_buf);
  }
  if (pt && pt->type == TUPLE_CSTRING) {
    snprintf(s_propagation_buf, sizeof(s_propagation_buf), "%s",
             pt->value->cstring);
    text_layer_set_text(s_propagation, s_propagation_buf);
  }
  if (kt || at || st || pt) {
    text_layer_set_text(s_status, "");
  }
}

static TextLayer *make_label(GRect frame, const char *text, GFont font,
                             GTextAlignment align) {
  TextLayer *layer = text_layer_create(frame);
  text_layer_set_text(layer, text);
  text_layer_set_font(layer, font);
  text_layer_set_text_alignment(layer, align);
  text_layer_set_background_color(layer, GColorClear);
  return layer;
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);
  window_set_background_color(window, GColorBlack);

  GFont title_font = fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD);
  GFont row_font = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
  GFont small_font = fonts_get_system_font(FONT_KEY_GOTHIC_14);

  s_title = make_label(GRect(0, 0, bounds.size.w, 22), "Solar", title_font,
                       GTextAlignmentCenter);
  s_kindex = make_label(GRect(8, 26, bounds.size.w - 16, 28), "K  --",
                        row_font, GTextAlignmentLeft);
  s_aindex = make_label(GRect(8, 54, bounds.size.w - 16, 28), "A  --",
                        row_font, GTextAlignmentLeft);
  s_sfi = make_label(GRect(8, 82, bounds.size.w - 16, 28), "SFI --",
                     row_font, GTextAlignmentLeft);
  s_propagation =
      make_label(GRect(0, bounds.size.h - 40, bounds.size.w, 22), "",
                 title_font, GTextAlignmentCenter);
  s_status = make_label(GRect(0, bounds.size.h - 18, bounds.size.w, 16),
                        "Loading...", small_font, GTextAlignmentCenter);

  text_layer_set_text_color(s_title, GColorWhite);
  text_layer_set_text_color(s_kindex, GColorWhite);
  text_layer_set_text_color(s_aindex, GColorWhite);
  text_layer_set_text_color(s_sfi, GColorWhite);
  text_layer_set_text_color(s_propagation, GColorYellow);
  text_layer_set_text_color(s_status, GColorLightGray);

  layer_add_child(root, text_layer_get_layer(s_title));
  layer_add_child(root, text_layer_get_layer(s_kindex));
  layer_add_child(root, text_layer_get_layer(s_aindex));
  layer_add_child(root, text_layer_get_layer(s_sfi));
  layer_add_child(root, text_layer_get_layer(s_propagation));
  layer_add_child(root, text_layer_get_layer(s_status));

  cw_comm_set_inbox_handler(inbox_handler);
  cw_comm_send_action(CW_ACTION_FETCH_SOLAR);
}

static void window_unload(Window *window) {
  (void)window;
  cw_comm_set_inbox_handler(NULL);
  text_layer_destroy(s_title);
  text_layer_destroy(s_kindex);
  text_layer_destroy(s_aindex);
  text_layer_destroy(s_sfi);
  text_layer_destroy(s_propagation);
  text_layer_destroy(s_status);
  s_title = s_kindex = s_aindex = s_sfi = s_propagation = s_status = NULL;
}

void cw_solar_window_push(void) {
  if (!s_window) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
                                             .load = window_load,
                                             .unload = window_unload,
                                         });
  }
  window_stack_push(s_window, true);
}
