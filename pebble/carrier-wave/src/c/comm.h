#pragma once

#include <pebble.h>

// Action codes sent from watch -> phone in the ACTION key.
#define CW_ACTION_FETCH_SOLAR   1
#define CW_ACTION_FETCH_SPOTS   2
#define CW_ACTION_FETCH_SESSION 3
#define CW_ACTION_LOG_QSO       4
#define CW_ACTION_FETCH_MEMORIES 5
#define CW_ACTION_RECALL_MEMORY  6

// Status codes sent phone -> watch in the STATUS key.
#define CW_STATUS_OK             0
#define CW_STATUS_PENDING        1
#define CW_STATUS_NETWORK_ERROR  2
#define CW_STATUS_BRIDGE_ERROR   3
#define CW_STATUS_NO_SESSION     4

typedef void (*cw_inbox_handler_t)(DictionaryIterator *iter);

// Initialise AppMessage with reasonable inbox/outbox sizes and dispatch
// inbound messages to the currently-registered window handler.
void cw_comm_init(void);
void cw_comm_deinit(void);

// Set the active inbound handler. Each window registers itself on push and
// clears on pop. Only one handler is active at a time.
void cw_comm_set_inbox_handler(cw_inbox_handler_t handler);

// Send a single ACTION key with no payload.
void cw_comm_send_action(uint32_t action);

// Send an ACTION key with an integer payload in MEMORY_RECALL_ID.
void cw_comm_send_recall(uint32_t memory_id);
