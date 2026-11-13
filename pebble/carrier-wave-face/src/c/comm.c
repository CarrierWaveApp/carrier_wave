#include "comm.h"

static cw_inbox_handler_t s_handler = NULL;

static void inbox_received(DictionaryIterator *iter, void *ctx) {
  (void)ctx;
  if (s_handler) {
    s_handler(iter);
  }
}

static void inbox_dropped(AppMessageResult reason, void *ctx) {
  (void)ctx;
  APP_LOG(APP_LOG_LEVEL_WARNING, "inbox dropped: %d", (int)reason);
}

void cw_comm_init(cw_inbox_handler_t handler) {
  s_handler = handler;
  app_message_register_inbox_received(inbox_received);
  app_message_register_inbox_dropped(inbox_dropped);
  app_message_open(512, 128);
}

void cw_comm_deinit(void) {
  s_handler = NULL;
  app_message_deregister_callbacks();
}

void cw_comm_send_action(uint32_t action) {
  DictionaryIterator *out;
  if (app_message_outbox_begin(&out) != APP_MSG_OK) return;
  dict_write_uint32(out, MESSAGE_KEY_ACTION, action);
  app_message_outbox_send();
}
