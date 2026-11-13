#include <pebble.h>

#include "comm.h"
#include "menu_window.h"

static void init(void) {
  cw_comm_init();
  cw_menu_window_push();
}

static void deinit(void) {
  cw_comm_deinit();
}

int main(void) {
  init();
  app_event_loop();
  deinit();
}
