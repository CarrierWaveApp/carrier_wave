#include <pebble.h>
#include <stdlib.h>

#include "comm.h"

/* --- Layout ---
 *
 *   +------------------+
 *   | Thu        x     |  BT-loss marker top-right
 *   | Jul  14:32   72° |  date (left) + local time (large) + temp (right)
 *   | 17               |
 *   |     Z 19:32 +1   |  UTC (+1 when UTC date is ahead of local)
 *   |                  |
 *   | K 1  [=|=|=|=|=] |  label + bar
 *   | A 9  [=|=|=|=|=] |  label + bar
 *   | SFI  [=|=|=|=|=] |  label + bar
 *   |    Excellent     |  propagation
 *   +------------------+
 */

static Window *s_window;

/* Local time */
static TextLayer *s_local_time;
static char s_local_buf[8];

/* Date — left of the time, stacked lines */
static TextLayer *s_date;
static char s_date_buf[16];

/* Temperature — right of the time */
static TextLayer *s_temp;
static char s_temp_buf[8];

/* UTC time */
static TextLayer *s_utc_label;
static TextLayer *s_utc_time;
static char s_utc_buf[8];

/* UTC date offset vs local ("+1" in the evening, US timezones) */
static TextLayer *s_utc_delta;
static char s_utc_delta_buf[4];

/* Bluetooth-disconnected marker */
static TextLayer *s_bt_warn;

/* Battery — icon + percentage, top-right corner */
static Layer *s_battery;
static int s_battery_pct = 100;

/* Battery icon geometry */
#define BATT_BODY_W 20
#define BATT_BODY_H 11
#define BATT_NUB_W 2
#define BATT_NUB_H 5
#define BATT_RADIUS 3
#define BATT_ICON_W (BATT_BODY_W + BATT_NUB_W)

/* Band condition labels */
static TextLayer *s_k_layer;
static TextLayer *s_a_layer;
static TextLayer *s_sfi_layer;
static char s_k_buf[12];
static char s_a_buf[12];
static char s_sfi_buf[16];

/* Stoplight bars — custom drawing layer */
static Layer *s_bars_layer;

/* Propagation summary */
static TextLayer *s_prop;
static char s_prop_buf[16];

/* Custom Routed Gothic fonts (drafting/Leroy lettering style) */
static GFont s_font_time;
static GFont s_font_utc;
static GFont s_font_date;
static GFont s_font_temp;

/* Stored solar values */
static char s_k_val[8] = "--";
static char s_a_val[8] = "--";
static char s_sfi_val[8] = "--";

/* Stored temperature (°F, from phone via Open-Meteo) */
static char s_temp_val[8] = "--";

/* Solar refresh: every 30 minutes */
#define SOLAR_REFRESH_MINUTES 30
static int s_ticks_since_solar = 0;

/* Solar data older than this is drawn dimmed (3 missed refreshes) */
#define SOLAR_STALE_SECONDS (90 * 60)
static time_t s_last_solar = 0;
static bool s_solar_stale = false;

/* Bar drawing constants */
#define BAR_SEGMENTS 3
#define BAR_HEIGHT 10
#define BAR_GAP 2
#define BAR_ROW_SPACING 4
#define LABEL_WIDTH 66
#define BAR_MARGIN 6

/* --- Color helpers matching Carrier Wave iOS Solar view --- */

/* Green-to-red gradient for K and A bars (low = good) */
static GColor bar_color_low_good(int seg) {
  if (seg == 0) return GColorGreen;
  if (seg == 1) return GColorChromeYellow;
  return GColorRed;
}

/* Red-to-green gradient for SFI bar (high = good) */
static GColor bar_color_high_good(int seg) {
  if (seg == 0) return GColorRed;
  if (seg == 1) return GColorChromeYellow;
  return GColorGreen;
}

/* Value color for the text labels */
static GColor color_for_k(const char *val) {
  if (val[0] == '-') return GColorLightGray;
  int num = atoi(val);
  if (num <= 1) return GColorGreen;
  if (num <= 3) return GColorYellow;
  if (num <= 4) return GColorOrange;
  return GColorRed;
}

static GColor color_for_a(const char *val) {
  if (val[0] == '-') return GColorLightGray;
  int num = atoi(val);
  if (num <= 7) return GColorGreen;
  if (num <= 15) return GColorYellow;
  if (num <= 29) return GColorOrange;
  return GColorRed;
}

static GColor color_for_sfi(const char *val) {
  if (val[0] == '-') return GColorLightGray;
  int num = atoi(val);
  if (num >= 150) return GColorGreen;
  if (num >= 100) return GColorYellow;
  if (num >= 70) return GColorOrange;
  return GColorRed;
}

/* Map value to active segment index (0-2) */
static int k_segment(const char *val) {
  if (val[0] == '-') return -1;
  int num = atoi(val);
  /* K: 0-2 good, 3-4 fair, 5+ poor */
  if (num <= 2) return 0;
  if (num <= 4) return 1;
  return 2;
}

static int a_segment(const char *val) {
  if (val[0] == '-') return -1;
  int num = atoi(val);
  /* A: 0-7 good, 8-29 fair, 30+ poor */
  if (num <= 7) return 0;
  if (num <= 29) return 1;
  return 2;
}

static int sfi_segment(const char *val) {
  if (val[0] == '-') return -1;
  int num = atoi(val);
  /* SFI: <70 poor, 70-149 fair, 150+ good */
  if (num < 70) return 0;
  if (num < 150) return 1;
  return 2;
}

/* Draw a single stoplight bar */
static void draw_bar(GContext *ctx, int bar_x, int bar_y, int bar_w,
                     int active, GColor (*color_fn)(int)) {
  int total_gaps = (BAR_SEGMENTS - 1) * BAR_GAP;
  int seg_w = (bar_w - total_gaps) / BAR_SEGMENTS;

  for (int idx = 0; idx < BAR_SEGMENTS; idx++) {
    int sx = bar_x + idx * (seg_w + BAR_GAP);
    GRect seg = GRect(sx, bar_y, seg_w, BAR_HEIGHT);

    graphics_context_set_fill_color(ctx, color_fn(idx));
    graphics_fill_rect(ctx, seg, 1, GCornersAll);

    if (idx == active) {
      /* Active segment: white outline (dimmed when data is stale) */
      graphics_context_set_stroke_color(
        ctx, s_solar_stale ? PBL_IF_COLOR_ELSE(GColorDarkGray, GColorLightGray)
                           : GColorWhite);
      graphics_draw_rect(ctx, seg);
    } else {
      /* Dim inactive: draw alternating black lines */
      graphics_context_set_stroke_color(ctx, GColorBlack);
      for (int row = bar_y + 1; row < bar_y + BAR_HEIGHT - 1; row += 2) {
        graphics_draw_line(ctx, GPoint(sx + 1, row),
                           GPoint(sx + seg_w - 2, row));
      }
    }
  }
}

/* Bars layer update callback — draws all three stacked bars */
static void bars_update_proc(Layer *layer, GContext *ctx) {
  GRect bounds = layer_get_bounds(layer);
  int bar_x = LABEL_WIDTH;
  int bar_w = bounds.size.w - LABEL_WIDTH - BAR_MARGIN;
  int row_h = BAR_HEIGHT + BAR_ROW_SPACING;

  /* K bar */
  draw_bar(ctx, bar_x, 0, bar_w,
           k_segment(s_k_val), bar_color_low_good);

  /* A bar */
  draw_bar(ctx, bar_x, row_h, bar_w,
           a_segment(s_a_val), bar_color_low_good);

  /* SFI bar */
  draw_bar(ctx, bar_x, row_h * 2, bar_w,
           sfi_segment(s_sfi_val), bar_color_high_good);
}

static void update_band_display(void) {
  snprintf(s_k_buf, sizeof(s_k_buf), "K %s", s_k_val);
  snprintf(s_a_buf, sizeof(s_a_buf), "A %s", s_a_val);
  snprintf(s_sfi_buf, sizeof(s_sfi_buf), "SFI %s", s_sfi_val);

  text_layer_set_text(s_k_layer, s_k_buf);
  text_layer_set_text(s_a_layer, s_a_buf);
  text_layer_set_text(s_sfi_layer, s_sfi_buf);

  if (s_solar_stale) {
    GColor dim = PBL_IF_COLOR_ELSE(GColorDarkGray, GColorLightGray);
    text_layer_set_text_color(s_k_layer, dim);
    text_layer_set_text_color(s_a_layer, dim);
    text_layer_set_text_color(s_sfi_layer, dim);
  } else {
    text_layer_set_text_color(s_k_layer, color_for_k(s_k_val));
    text_layer_set_text_color(s_a_layer, color_for_a(s_a_val));
    text_layer_set_text_color(s_sfi_layer, color_for_sfi(s_sfi_val));
  }

  if (s_bars_layer) {
    layer_mark_dirty(s_bars_layer);
  }
}

/* Temperature layer: "72°" once data arrives, blank until then */
static void update_temp_display(void) {
  if (s_temp_val[0] == '-') {
    s_temp_buf[0] = '\0';
  } else {
    snprintf(s_temp_buf, sizeof(s_temp_buf), "%s\xC2\xB0", s_temp_val);
  }
  text_layer_set_text(s_temp, s_temp_buf);
}

static void inbox_handler(DictionaryIterator *iter) {
  Tuple *kt = dict_find(iter, MESSAGE_KEY_K_INDEX);
  Tuple *at = dict_find(iter, MESSAGE_KEY_A_INDEX);
  Tuple *st = dict_find(iter, MESSAGE_KEY_SOLAR_FLUX);
  Tuple *pt = dict_find(iter, MESSAGE_KEY_PROPAGATION);
  Tuple *tt = dict_find(iter, MESSAGE_KEY_TEMPERATURE);

  if (kt && kt->type == TUPLE_CSTRING) {
    strncpy(s_k_val, kt->value->cstring, sizeof(s_k_val) - 1);
  }
  if (at && at->type == TUPLE_CSTRING) {
    strncpy(s_a_val, at->value->cstring, sizeof(s_a_val) - 1);
  }
  if (st && st->type == TUPLE_CSTRING) {
    strncpy(s_sfi_val, st->value->cstring, sizeof(s_sfi_val) - 1);
  }
  if (pt && pt->type == TUPLE_CSTRING) {
    strncpy(s_prop_buf, pt->value->cstring, sizeof(s_prop_buf) - 1);
    text_layer_set_text(s_prop, s_prop_buf);
  }
  if (tt && tt->type == TUPLE_CSTRING) {
    strncpy(s_temp_val, tt->value->cstring, sizeof(s_temp_val) - 1);
    update_temp_display();
  }

  if (kt || at || st) {
    s_last_solar = time(NULL);
    s_solar_stale = false;
  }
  update_band_display();
}

static void update_time(struct tm *local) {
  strftime(s_local_buf, sizeof(s_local_buf), "%H:%M", local);
  text_layer_set_text(s_local_time, s_local_buf);

  strftime(s_date_buf, sizeof(s_date_buf), "%a\n%b\n%d", local);
  text_layer_set_text(s_date, s_date_buf);

  /* Capture before gmtime() — it may share localtime()'s static buffer */
  int local_year = local->tm_year;
  int local_yday = local->tm_yday;

  time_t now = time(NULL);
  struct tm *utc = gmtime(&now);
  if (utc) {
    strftime(s_utc_buf, sizeof(s_utc_buf), "%H:%M", utc);
    text_layer_set_text(s_utc_time, s_utc_buf);

    int delta = 0;
    if (utc->tm_year != local_year) {
      delta = (utc->tm_year > local_year) ? 1 : -1;
    } else if (utc->tm_yday != local_yday) {
      delta = (utc->tm_yday > local_yday) ? 1 : -1;
    }
    if (delta != 0) {
      snprintf(s_utc_delta_buf, sizeof(s_utc_delta_buf), "%+d", delta);
    } else {
      s_utc_delta_buf[0] = '\0';
    }
    text_layer_set_text(s_utc_delta, s_utc_delta_buf);
  }
}

static void tick_handler(struct tm *tick_time, TimeUnits units) {
  (void)units;
  update_time(tick_time);

  s_ticks_since_solar++;
  if (s_ticks_since_solar >= SOLAR_REFRESH_MINUTES) {
    s_ticks_since_solar = 0;
    cw_comm_send_action(CW_ACTION_FETCH_SOLAR);
  }

  bool stale = (s_last_solar != 0) &&
               (time(NULL) - s_last_solar > SOLAR_STALE_SECONDS);
  if (stale != s_solar_stale) {
    s_solar_stale = stale;
    update_band_display();
  }
}

/* Battery layer: a filled battery icon in the top-right corner. The
 * proportional fill (and its color) shows charge at a glance. */
static void battery_update_proc(Layer *layer, GContext *ctx) {
  GRect bounds = layer_get_bounds(layer);
  int pct = s_battery_pct;
  bool low = pct <= 20;

  /* Icon — rounded outline + terminal nub, echoing the Routed Gothic strokes */
  int bx = 0;
  int by = (bounds.size.h - BATT_BODY_H) / 2;
  GColor outline = GColorLightGray;
  graphics_context_set_stroke_color(ctx, outline);
  graphics_draw_round_rect(ctx, GRect(bx, by, BATT_BODY_W, BATT_BODY_H),
                           BATT_RADIUS);
  graphics_context_set_fill_color(ctx, outline);
  graphics_fill_rect(ctx,
    GRect(bx + BATT_BODY_W, by + (BATT_BODY_H - BATT_NUB_H) / 2,
          BATT_NUB_W, BATT_NUB_H),
    1, GCornerTopRight | GCornerBottomRight);

  /* Fill proportional to charge; color by level. Left corners rounded to
   * nest inside the body; right edge square so it reads as a level. */
  GColor fill = low ? GColorRed : (pct <= 40 ? GColorChromeYellow : GColorGreen);
  fill = PBL_IF_COLOR_ELSE(fill, GColorWhite);
  int inner_w = BATT_BODY_W - 2;
  int fill_w = (inner_w * pct) / 100;
  if (fill_w > 0) {
    graphics_context_set_fill_color(ctx, fill);
    graphics_fill_rect(ctx, GRect(bx + 1, by + 1, fill_w, BATT_BODY_H - 2),
                       BATT_RADIUS - 1, GCornerTopLeft | GCornerBottomLeft);
  }
}

static void update_battery(BatteryChargeState state) {
  s_battery_pct = state.charge_percent;
  if (s_battery) {
    layer_mark_dirty(s_battery);
  }
}

static void battery_handler(BatteryChargeState state) {
  update_battery(state);
}

static void bt_connection_handler(bool connected) {
  layer_set_hidden(text_layer_get_layer(s_bt_warn), connected);
  if (!connected) {
    vibes_double_pulse();
  }
}

static TextLayer *make_text(Layer *parent, GRect frame, GFont font,
                            GColor color, GTextAlignment align) {
  TextLayer *layer = text_layer_create(frame);
  text_layer_set_font(layer, font);
  text_layer_set_text_alignment(layer, align);
  text_layer_set_text_color(layer, color);
  text_layer_set_background_color(layer, GColorClear);
  layer_add_child(parent, text_layer_get_layer(layer));
  return layer;
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);
  int ctr = bounds.size.w / 2;
  window_set_background_color(window, GColorBlack);

  s_font_time = fonts_load_custom_font(
    resource_get_handle(RESOURCE_ID_FONT_ROUTED_GOTHIC_40));
  s_font_utc = fonts_load_custom_font(
    resource_get_handle(RESOURCE_ID_FONT_ROUTED_GOTHIC_26));
  s_font_date = fonts_load_custom_font(
    resource_get_handle(RESOURCE_ID_FONT_ROUTED_GOTHIC_18));
  s_font_temp = fonts_load_custom_font(
    resource_get_handle(RESOURCE_ID_FONT_ROUTED_GOTHIC_20));

  GFont big = s_font_time;
  GFont med = s_font_utc;
  GFont label_font = fonts_get_system_font(FONT_KEY_GOTHIC_14);
  GFont row_font = fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD);
  GFont prop_font = fonts_get_system_font(FONT_KEY_GOTHIC_18);
  /* Side columns are ~44px; every string must fit unwrapped or TextLayer
   * ellipsizes. Date: 18px, three stacked lines (widest "Wed"/"May" = 35px).
   * Temp: 20px (worst-case "104°" = 43px). */
  GFont date_font = s_font_date;
  GFont temp_font = s_font_temp;

  /* Local time — large, centered; date and temperature flank it */
  int local_y = 2;
  s_local_time = make_text(root,
    GRect(0, local_y, bounds.size.w, 50),
    big, GColorWhite, GTextAlignmentCenter);

  /* Side columns: whatever the centered 40px time leaves over
   * (Routed Gothic runs wider than LECO at equal height) */
  int side_w = (bounds.size.w - 112) / 2;
  if (side_w < 20) side_w = 20;

  /* Date — left of the time, three stacked lines ("Thu" / "Jul" / "17") */
  s_date = make_text(root,
    GRect(2, local_y, side_w, 68),
    date_font, GColorLightGray, GTextAlignmentLeft);

  /* Temperature — right of the time */
  s_temp = make_text(root,
    GRect(bounds.size.w - side_w - 2, local_y + 16, side_w, 26),
    temp_font, GColorLightGray, GTextAlignmentRight);

  /* Battery icon — centered above the temperature column */
  int temp_x = bounds.size.w - side_w - 2;
  int batt_x = temp_x + side_w / 2 - BATT_ICON_W / 2;
  int batt_x_max = bounds.size.w - BATT_ICON_W - 2;
  if (batt_x > batt_x_max) batt_x = batt_x_max;
  if (batt_x < 0) batt_x = 0;
  s_battery = layer_create(GRect(batt_x, 2, BATT_ICON_W, 14));
  layer_set_update_proc(s_battery, battery_update_proc);
  layer_add_child(root, s_battery);
  update_battery(battery_state_service_peek());

  /* BT-loss marker — left of the battery, hidden while connected */
  s_bt_warn = make_text(root,
    GRect(batt_x - 16, 0, 14, 16),
    label_font, PBL_IF_COLOR_ELSE(GColorRed, GColorWhite),
    GTextAlignmentRight);
  text_layer_set_text(s_bt_warn, "x");
  layer_set_hidden(text_layer_get_layer(s_bt_warn),
                   connection_service_peek_pebble_app_connection());

  /* UTC label + time — below the time block AND the 3-line date column */
  int utc_y = local_y + 66;
  s_utc_label = make_text(root,
    GRect(ctr - 70, utc_y + 2, 24, 18),
    label_font, GColorLightGray, GTextAlignmentRight);
  text_layer_set_text(s_utc_label, "Z");

  s_utc_time = make_text(root,
    GRect(ctr - 42, utc_y - 2, 84, 32),
    med, GColorYellow, GTextAlignmentLeft);

  /* UTC day offset ("+1") — right of the UTC time */
  s_utc_delta = make_text(root,
    GRect(ctr + 44, utc_y + 2, 28, 18),
    label_font, GColorLightGray, GTextAlignmentLeft);

  /* Band conditions — three stacked rows, label left + bar right */
  int row_h = BAR_HEIGHT + BAR_ROW_SPACING;
  int band_y = utc_y + 32;

  /* Text labels — left-aligned, vertically centered with bars */
  int text_offset = (BAR_HEIGHT - 18) / 2 - 2; /* center 18px font in bar */
  s_k_layer = make_text(root,
    GRect(BAR_MARGIN, band_y + text_offset, LABEL_WIDTH - BAR_MARGIN, 20),
    row_font, GColorLightGray, GTextAlignmentLeft);

  s_a_layer = make_text(root,
    GRect(BAR_MARGIN, band_y + row_h + text_offset, LABEL_WIDTH - BAR_MARGIN, 20),
    row_font, GColorLightGray, GTextAlignmentLeft);

  s_sfi_layer = make_text(root,
    GRect(BAR_MARGIN, band_y + row_h * 2 + text_offset, LABEL_WIDTH - BAR_MARGIN, 20),
    row_font, GColorLightGray, GTextAlignmentLeft);

  /* Bars drawing layer — covers all three bar rows */
  int bars_h = row_h * 3;
  s_bars_layer = layer_create(GRect(0, band_y, bounds.size.w, bars_h));
  layer_set_update_proc(s_bars_layer, bars_update_proc);
  layer_add_child(root, s_bars_layer);

  /* Propagation label at bottom */
  int prop_y = band_y + bars_h + 2;
  s_prop = make_text(root,
    GRect(0, prop_y, bounds.size.w, 18),
    prop_font, GColorYellow, GTextAlignmentCenter);
  text_layer_set_text(s_prop, "");

  update_band_display();
  update_temp_display();

  /* Set initial time */
  time_t now = time(NULL);
  struct tm *local_tm = localtime(&now);
  if (local_tm) {
    update_time(local_tm);
  }

  tick_timer_service_subscribe(MINUTE_UNIT, tick_handler);
  battery_state_service_subscribe(battery_handler);
  connection_service_subscribe((ConnectionHandlers){
    .pebble_app_connection_handler = bt_connection_handler,
  });
  cw_comm_send_action(CW_ACTION_FETCH_SOLAR);
}

static void window_unload(Window *window) {
  (void)window;
  tick_timer_service_unsubscribe();
  battery_state_service_unsubscribe();
  connection_service_unsubscribe();
  text_layer_destroy(s_local_time);
  text_layer_destroy(s_bt_warn);
  layer_destroy(s_battery);
  text_layer_destroy(s_date);
  text_layer_destroy(s_temp);
  text_layer_destroy(s_utc_label);
  text_layer_destroy(s_utc_time);
  text_layer_destroy(s_utc_delta);
  text_layer_destroy(s_k_layer);
  text_layer_destroy(s_a_layer);
  text_layer_destroy(s_sfi_layer);
  layer_destroy(s_bars_layer);
  text_layer_destroy(s_prop);
  fonts_unload_custom_font(s_font_time);
  fonts_unload_custom_font(s_font_utc);
  fonts_unload_custom_font(s_font_date);
  fonts_unload_custom_font(s_font_temp);
}

static void init(void) {
  cw_comm_init(inbox_handler);

  s_window = window_create();
  window_set_window_handlers(s_window, (WindowHandlers){
    .load = window_load,
    .unload = window_unload,
  });
  window_stack_push(s_window, true);
}

static void deinit(void) {
  cw_comm_deinit();
  window_destroy(s_window);
}

int main(void) {
  init();
  app_event_loop();
  deinit();
}
