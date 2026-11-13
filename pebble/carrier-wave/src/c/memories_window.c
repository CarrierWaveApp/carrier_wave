#include "memories_window.h"

#include <pebble.h>

#include "comm.h"

#define MAX_MEMORIES 8
#define NAME_BUF_LEN 24
#define SUBTITLE_BUF_LEN 24

static Window *s_window = NULL;
static SimpleMenuLayer *s_menu = NULL;
static SimpleMenuSection s_sections[1];
static SimpleMenuItem s_items[MAX_MEMORIES];
static TextLayer *s_status = NULL;

static int s_count = 0;
static int s_mem_ids[MAX_MEMORIES];
static char s_names[MAX_MEMORIES][NAME_BUF_LEN];
static char s_subtitles[MAX_MEMORIES][SUBTITLE_BUF_LEN];

static void rebuild_menu(void);

static void on_select(int index, void *ctx) {
  (void)ctx;
  if (index < 0 || index >= s_count) return;
  cw_comm_send_recall((uint32_t)s_mem_ids[index]);
  vibes_short_pulse();
}

static void inbox_handler(DictionaryIterator *iter) {
  Tuple *status = dict_find(iter, MESSAGE_KEY_STATUS);
  if (status) {
    /* Recall response — just vibrate on success */
    if ((int)status->value->int32 == CW_STATUS_OK) {
      vibes_double_pulse();
    }
    return;
  }

  Tuple *count_t = dict_find(iter, MESSAGE_KEY_MEMORY_COUNT);
  if (count_t) {
    s_count = 0;
    if (s_status) {
      text_layer_set_text(s_status, "");
    }
    return;
  }

  Tuple *idx_t = dict_find(iter, MESSAGE_KEY_MEMORY_INDEX);
  Tuple *id_t = dict_find(iter, MESSAGE_KEY_MEMORY_ID);
  Tuple *name_t = dict_find(iter, MESSAGE_KEY_MEMORY_NAME);
  Tuple *text_t = dict_find(iter, MESSAGE_KEY_MEMORY_FREQ);

  if (idx_t && id_t && name_t) {
    int idx = (int)idx_t->value->int32;
    if (idx < 0 || idx >= MAX_MEMORIES) return;

    s_mem_ids[idx] = (int)id_t->value->int32;
    strncpy(s_names[idx], name_t->value->cstring, NAME_BUF_LEN - 1);
    s_names[idx][NAME_BUF_LEN - 1] = '\0';

    /* Subtitle: the CW message text (truncated) */
    const char *text = text_t ? text_t->value->cstring : "";
    snprintf(s_subtitles[idx], SUBTITLE_BUF_LEN, "%s", text);

    if (idx + 1 > s_count) {
      s_count = idx + 1;
    }
    rebuild_menu();
  }
}

static void rebuild_menu(void) {
  if (!s_window) return;

  Layer *root = window_get_root_layer(s_window);
  GRect bounds = layer_get_bounds(root);

  if (s_menu) {
    simple_menu_layer_destroy(s_menu);
    s_menu = NULL;
  }

  if (s_count == 0) {
    if (s_status) {
      text_layer_set_text(s_status, "No memories");
    }
    return;
  }

  for (int idx = 0; idx < s_count; idx++) {
    s_items[idx] = (SimpleMenuItem){
        .title = s_names[idx],
        .subtitle = s_subtitles[idx],
        .callback = on_select,
    };
  }
  s_sections[0] = (SimpleMenuSection){
      .num_items = s_count,
      .items = s_items,
  };

  s_menu = simple_menu_layer_create(bounds, s_window, s_sections, 1, NULL);
  layer_add_child(root, simple_menu_layer_get_layer(s_menu));
}

static void window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);
  window_set_background_color(window, GColorBlack);

  GFont font = fonts_get_system_font(FONT_KEY_GOTHIC_18);
  s_status = text_layer_create(
      GRect(0, bounds.size.h / 2 - 12, bounds.size.w, 24));
  text_layer_set_font(s_status, font);
  text_layer_set_text_alignment(s_status, GTextAlignmentCenter);
  text_layer_set_text_color(s_status, GColorLightGray);
  text_layer_set_background_color(s_status, GColorClear);
  text_layer_set_text(s_status, "Loading...");
  layer_add_child(root, text_layer_get_layer(s_status));

  s_count = 0;
  cw_comm_set_inbox_handler(inbox_handler);
  cw_comm_send_action(CW_ACTION_FETCH_MEMORIES);
}

static void window_unload(Window *window) {
  (void)window;
  cw_comm_set_inbox_handler(NULL);
  if (s_menu) {
    simple_menu_layer_destroy(s_menu);
    s_menu = NULL;
  }
  text_layer_destroy(s_status);
  s_status = NULL;
}

void cw_memories_window_push(void) {
  if (!s_window) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
                                             .load = window_load,
                                             .unload = window_unload,
                                         });
  }
  window_stack_push(s_window, true);
}
