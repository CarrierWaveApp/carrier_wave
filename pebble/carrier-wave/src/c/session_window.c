#include "session_window.h"

#include <pebble.h>

#include "comm.h"

static Window *s_window = NULL;
static TextLayer *s_title = NULL;
static TextLayer *s_park = NULL;
static TextLayer *s_freq = NULL;
static TextLayer *s_mode = NULL;
static TextLayer *s_count = NULL;
static TextLayer *s_last_call = NULL;
static TextLayer *s_status = NULL;

static char s_park_buf[40];
static char s_freq_buf[24];
static char s_mode_buf[16];
static char s_count_buf[20];
static char s_last_call_buf[24];
static char s_status_buf[40];

static bool s_session_active = false;
static bool s_log_in_flight = false;

static void show_idle(void) {
  text_layer_set_text(s_park, "No active session");
  text_layer_set_text(s_freq, "");
  text_layer_set_text(s_mode, "");
  text_layer_set_text(s_count, "");
  text_layer_set_text(s_last_call, "");
  text_layer_set_text(s_status, "Open Field on iPhone");
  s_session_active = false;
}

static void inbox_handler(DictionaryIterator *iter) {
  Tuple *active_t = dict_find(iter, MESSAGE_KEY_SESSION_ACTIVE);
  Tuple *park_ref_t = dict_find(iter, MESSAGE_KEY_SESSION_PARK_REF);
  Tuple *park_name_t = dict_find(iter, MESSAGE_KEY_SESSION_PARK_NAME);
  Tuple *freq_t = dict_find(iter, MESSAGE_KEY_SESSION_FREQ);
  Tuple *mode_t = dict_find(iter, MESSAGE_KEY_SESSION_MODE);
  Tuple *count_t = dict_find(iter, MESSAGE_KEY_SESSION_QSO_COUNT);
  Tuple *last_t = dict_find(iter, MESSAGE_KEY_SESSION_LAST_CALL);
  Tuple *status_t = dict_find(iter, MESSAGE_KEY_STATUS);
  Tuple *err_t = dict_find(iter, MESSAGE_KEY_ERROR_TEXT);

  if (status_t && status_t->type == TUPLE_INT) {
    int status = status_t->value->int32;
    s_log_in_flight = false;
    switch (status) {
      case CW_STATUS_OK:
        snprintf(s_status_buf, sizeof(s_status_buf), "Logged");
        vibes_short_pulse();
        break;
      case CW_STATUS_BRIDGE_ERROR:
        snprintf(s_status_buf, sizeof(s_status_buf), "Bridge offline");
        break;
      case CW_STATUS_NO_SESSION:
        snprintf(s_status_buf, sizeof(s_status_buf), "No active session");
        break;
      case CW_STATUS_NETWORK_ERROR:
        snprintf(s_status_buf, sizeof(s_status_buf), "Network error");
        break;
      default:
        if (err_t && err_t->type == TUPLE_CSTRING) {
          snprintf(s_status_buf, sizeof(s_status_buf), "%s",
                   err_t->value->cstring);
        } else {
          snprintf(s_status_buf, sizeof(s_status_buf), "Error %d", status);
        }
        break;
    }
    text_layer_set_text(s_status, s_status_buf);
  }

  if (active_t && active_t->type == TUPLE_INT) {
    s_session_active = active_t->value->int32 != 0;
    if (!s_session_active) {
      show_idle();
      return;
    }
  }

  if (park_ref_t || park_name_t) {
    const char *ref =
        park_ref_t && park_ref_t->type == TUPLE_CSTRING
            ? park_ref_t->value->cstring
            : "";
    const char *name =
        park_name_t && park_name_t->type == TUPLE_CSTRING
            ? park_name_t->value->cstring
            : "";
    if (ref[0] && name[0]) {
      snprintf(s_park_buf, sizeof(s_park_buf), "%s — %s", ref, name);
    } else if (ref[0]) {
      snprintf(s_park_buf, sizeof(s_park_buf), "%s", ref);
    } else {
      snprintf(s_park_buf, sizeof(s_park_buf), "%s", name);
    }
    text_layer_set_text(s_park, s_park_buf);
  }
  if (freq_t && freq_t->type == TUPLE_CSTRING) {
    snprintf(s_freq_buf, sizeof(s_freq_buf), "%s MHz",
             freq_t->value->cstring);
    text_layer_set_text(s_freq, s_freq_buf);
  }
  if (mode_t && mode_t->type == TUPLE_CSTRING) {
    snprintf(s_mode_buf, sizeof(s_mode_buf), "%s", mode_t->value->cstring);
    text_layer_set_text(s_mode, s_mode_buf);
  }
  if (count_t && count_t->type == TUPLE_INT) {
    snprintf(s_count_buf, sizeof(s_count_buf), "%d QSOs",
             (int)count_t->value->int32);
    text_layer_set_text(s_count, s_count_buf);
  }
  if (last_t && last_t->type == TUPLE_CSTRING) {
    snprintf(s_last_call_buf, sizeof(s_last_call_buf), "Last: %s",
             last_t->value->cstring);
    text_layer_set_text(s_last_call, s_last_call_buf);
  }

  if (s_session_active && s_status_buf[0] == 0) {
    text_layer_set_text(s_status, "SELECT to log");
  }
}

static void select_click(ClickRecognizerRef recognizer, void *context) {
  (void)recognizer;
  (void)context;
  if (!s_session_active) {
    text_layer_set_text(s_status, "No active session");
    return;
  }
  if (s_log_in_flight) {
    return;
  }
  s_log_in_flight = true;
  text_layer_set_text(s_status, "Logging...");
  cw_comm_send_action(CW_ACTION_LOG_QSO);
}

static void up_click(ClickRecognizerRef recognizer, void *context) {
  (void)recognizer;
  (void)context;
  cw_comm_send_action(CW_ACTION_FETCH_SESSION);
  text_layer_set_text(s_status, "Refreshing...");
}

static void click_provider(void *context) {
  (void)context;
  window_single_click_subscribe(BUTTON_ID_SELECT, select_click);
  window_single_click_subscribe(BUTTON_ID_UP, up_click);
}

static TextLayer *make_label(GRect frame, GFont font, GColor color,
                             GTextAlignment align) {
  TextLayer *layer = text_layer_create(frame);
  text_layer_set_font(layer, font);
  text_layer_set_text_color(layer, color);
  text_layer_set_text_alignment(layer, align);
  text_layer_set_background_color(layer, GColorClear);
  return layer;
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);
  window_set_background_color(window, GColorBlack);

  GFont title_font = fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD);
  GFont row_font = fonts_get_system_font(FONT_KEY_GOTHIC_18);
  GFont small_font = fonts_get_system_font(FONT_KEY_GOTHIC_14);

  s_title = make_label(GRect(0, 0, bounds.size.w, 22), title_font,
                       GColorYellow, GTextAlignmentCenter);
  text_layer_set_text(s_title, "Session");
  s_park = make_label(GRect(8, 24, bounds.size.w - 16, 22), title_font,
                      GColorWhite, GTextAlignmentLeft);
  s_freq = make_label(GRect(8, 48, bounds.size.w - 16, 22), row_font,
                      GColorWhite, GTextAlignmentLeft);
  s_mode = make_label(GRect(8, 70, bounds.size.w - 16, 22), row_font,
                      GColorLightGray, GTextAlignmentLeft);
  s_count = make_label(GRect(8, 92, bounds.size.w - 16, 22), row_font,
                       GColorWhite, GTextAlignmentLeft);
  s_last_call = make_label(GRect(8, 114, bounds.size.w - 16, 22), row_font,
                           GColorYellow, GTextAlignmentLeft);
  s_status = make_label(GRect(0, bounds.size.h - 18, bounds.size.w, 16),
                        small_font, GColorLightGray, GTextAlignmentCenter);

  layer_add_child(root, text_layer_get_layer(s_title));
  layer_add_child(root, text_layer_get_layer(s_park));
  layer_add_child(root, text_layer_get_layer(s_freq));
  layer_add_child(root, text_layer_get_layer(s_mode));
  layer_add_child(root, text_layer_get_layer(s_count));
  layer_add_child(root, text_layer_get_layer(s_last_call));
  layer_add_child(root, text_layer_get_layer(s_status));

  s_status_buf[0] = 0;
  show_idle();
  text_layer_set_text(s_status, "Loading session...");

  window_set_click_config_provider(window, click_provider);
  cw_comm_set_inbox_handler(inbox_handler);
  cw_comm_send_action(CW_ACTION_FETCH_SESSION);
}

static void window_unload(Window *window) {
  (void)window;
  cw_comm_set_inbox_handler(NULL);
  text_layer_destroy(s_title);
  text_layer_destroy(s_park);
  text_layer_destroy(s_freq);
  text_layer_destroy(s_mode);
  text_layer_destroy(s_count);
  text_layer_destroy(s_last_call);
  text_layer_destroy(s_status);
  s_title = s_park = s_freq = s_mode = s_count = s_last_call = s_status = NULL;
}

void cw_session_window_push(void) {
  if (!s_window) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
                                             .load = window_load,
                                             .unload = window_unload,
                                         });
  }
  window_stack_push(s_window, true);
}
