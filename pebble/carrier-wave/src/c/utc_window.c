#include "utc_window.h"

#include <pebble.h>
#include <time.h>

static Window *s_window = NULL;
static TextLayer *s_clock = NULL;
static TextLayer *s_label = NULL;
static TextLayer *s_date = NULL;
static char s_clock_buf[16];
static char s_date_buf[24];

static void update_clock(struct tm *now_utc) {
  strftime(s_clock_buf, sizeof(s_clock_buf), "%H:%M:%S", now_utc);
  strftime(s_date_buf, sizeof(s_date_buf), "%a %d %b", now_utc);
  text_layer_set_text(s_clock, s_clock_buf);
  text_layer_set_text(s_date, s_date_buf);
}

static void tick_handler(struct tm *tick_time, TimeUnits units) {
  (void)tick_time;
  (void)units;
  time_t now = time(NULL);
  struct tm *gmt = gmtime(&now);
  if (gmt) {
    update_clock(gmt);
  }
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);
  window_set_background_color(window, GColorBlack);

  GFont label_font = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
  GFont clock_font =
      fonts_get_system_font(FONT_KEY_BITHAM_42_LIGHT);
  GFont date_font = fonts_get_system_font(FONT_KEY_GOTHIC_18);

  s_label = text_layer_create(GRect(0, 14, bounds.size.w, 28));
  text_layer_set_text(s_label, "ZULU");
  text_layer_set_font(s_label, label_font);
  text_layer_set_text_alignment(s_label, GTextAlignmentCenter);
  text_layer_set_text_color(s_label, GColorYellow);
  text_layer_set_background_color(s_label, GColorClear);

  int clock_y = (bounds.size.h - 50) / 2;
  s_clock = text_layer_create(GRect(0, clock_y, bounds.size.w, 50));
  text_layer_set_font(s_clock, clock_font);
  text_layer_set_text_alignment(s_clock, GTextAlignmentCenter);
  text_layer_set_text_color(s_clock, GColorWhite);
  text_layer_set_background_color(s_clock, GColorClear);

  s_date = text_layer_create(GRect(0, bounds.size.h - 30, bounds.size.w, 22));
  text_layer_set_font(s_date, date_font);
  text_layer_set_text_alignment(s_date, GTextAlignmentCenter);
  text_layer_set_text_color(s_date, GColorLightGray);
  text_layer_set_background_color(s_date, GColorClear);

  layer_add_child(root, text_layer_get_layer(s_label));
  layer_add_child(root, text_layer_get_layer(s_clock));
  layer_add_child(root, text_layer_get_layer(s_date));

  time_t now = time(NULL);
  struct tm *gmt = gmtime(&now);
  if (gmt) {
    update_clock(gmt);
  }
  tick_timer_service_subscribe(SECOND_UNIT, tick_handler);
}

static void window_unload(Window *window) {
  (void)window;
  tick_timer_service_unsubscribe();
  text_layer_destroy(s_label);
  text_layer_destroy(s_clock);
  text_layer_destroy(s_date);
  s_label = s_clock = s_date = NULL;
}

void cw_utc_window_push(void) {
  if (!s_window) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
                                             .load = window_load,
                                             .unload = window_unload,
                                         });
  }
  window_stack_push(s_window, true);
}
