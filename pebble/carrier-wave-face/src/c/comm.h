#pragma once

#include <pebble.h>

#define CW_ACTION_FETCH_SOLAR 1

typedef void (*cw_inbox_handler_t)(DictionaryIterator *iter);

void cw_comm_init(cw_inbox_handler_t handler);
void cw_comm_deinit(void);
void cw_comm_send_action(uint32_t action);
