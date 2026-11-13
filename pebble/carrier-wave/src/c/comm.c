#include "comm.h"

static cw_inbox_handler_t s_inbox_handler = NULL;

static void inbox_received(DictionaryIterator *iter, void *context) {
  (void)context;
  if (s_inbox_handler) {
    s_inbox_handler(iter);
  }
}

static void inbox_dropped(AppMessageResult reason, void *context) {
  (void)context;
  APP_LOG(APP_LOG_LEVEL_WARNING, "AppMessage dropped: %d", (int)reason);
}

static void outbox_failed(DictionaryIterator *iter, AppMessageResult reason,
                          void *context) {
  (void)iter;
  (void)context;
  APP_LOG(APP_LOG_LEVEL_WARNING, "AppMessage outbox failed: %d", (int)reason);
}

void cw_comm_init(void) {
  app_message_register_inbox_received(inbox_received);
  app_message_register_inbox_dropped(inbox_dropped);
  app_message_register_outbox_failed(outbox_failed);
  // 1 KB inbox is enough for a single spot record or session snapshot.
  app_message_open(1024, 256);
}

void cw_comm_deinit(void) {
  s_inbox_handler = NULL;
  app_message_deregister_callbacks();
}

void cw_comm_set_inbox_handler(cw_inbox_handler_t handler) {
  s_inbox_handler = handler;
}

void cw_comm_send_action(uint32_t action) {
  DictionaryIterator *out;
  AppMessageResult open = app_message_outbox_begin(&out);
  if (open != APP_MSG_OK) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "outbox_begin failed: %d", (int)open);
    return;
  }
  dict_write_uint32(out, MESSAGE_KEY_ACTION, action);
  app_message_outbox_send();
}

void cw_comm_send_recall(uint32_t memory_id) {
  DictionaryIterator *out;
  AppMessageResult open = app_message_outbox_begin(&out);
  if (open != APP_MSG_OK) {
    APP_LOG(APP_LOG_LEVEL_WARNING, "outbox_begin failed: %d", (int)open);
    return;
  }
  dict_write_uint32(out, MESSAGE_KEY_ACTION, CW_ACTION_RECALL_MEMORY);
  dict_write_uint32(out, MESSAGE_KEY_MEMORY_RECALL_ID, memory_id);
  app_message_outbox_send();
}
