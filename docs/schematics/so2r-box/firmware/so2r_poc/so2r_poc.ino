// SO2R Box POC firmware - Heltec WiFi LoRa 32 V3 (ESP32-S3)
//
// Covers POC_BENCH_PLAN milestones 1-3:
//   1. OLED + button + one WS2812B (toolchain sanity)
//   2. I2C bring-up + 8-relay click test via MCP23017
//   3. Panel state machine: 4 buttons / 4 WS2812B LEDs / OLED status
//
// Hardware assumed:
//   Heltec V3 powered over USB-C
//   MCP23017 breakout on external I2C bus (4.7k pull-ups to 3V3)
//   8-channel 5V relay module driven from MCP23017 port B
//   4x tactile buttons -> GPIO 4-7, INPUT_PULLUP, other leg to GND
//   4x WS2812B chain   -> data on GPIO 2 (with the warm-finger reminder
//                         that REVIEW B6 is right and a 5V level shifter
//                         is mandatory for the real build)
//
// Serial commands @ 115200 (USB-CDC):
//   ?           help
//   scan        I2C scan on the external bus
//   walk        walking-bit across all 8 relays, 200 ms each
//   tst <0-7>   energise one relay (logical bit; polarity-aware)
//   pol         polarity-check helper (writes 0x01 and tells you what to look for)
//   inv         flip the active-low / active-high flag
//   off         release all relays
//
// Panel button mapping:
//   BTN1 -> select radio 1
//   BTN2 -> select radio 2
//   BTN3 -> band down
//   BTN4 -> band up

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_NeoPixel.h>

// ---------- Pin map ----------
// Avoids GPIO 33-38 (PSRAM bus on most current Heltec V3 production) and
// GPIO 8-14 (LoRa SX1262 SPI). Verify against your own board with a
// continuity tester before believing this comment.

constexpr int PIN_OLED_SDA = 17;
constexpr int PIN_OLED_SCL = 18;
constexpr int PIN_OLED_RST = 21;
constexpr int PIN_VEXT     = 36;   // active-LOW: enables OLED + Vext rail

constexpr int PIN_BUTTON[4] = {4, 5, 6, 7};
constexpr int PIN_NEOPIXEL  = 2;
constexpr int NUM_PIXELS    = 4;

constexpr int PIN_LORA_RST  = 12;  // held LOW so SX1262 stays silent (REVIEW)

constexpr int PIN_SDA_EXT   = 41;  // external I2C bus for MCP23017
constexpr int PIN_SCL_EXT   = 42;

// ---------- I2C / MCP23017 ----------
constexpr uint8_t MCP23017_ADDR = 0x20;  // A0=A1=A2=GND

constexpr uint8_t MCP_IODIRA = 0x00;
constexpr uint8_t MCP_IODIRB = 0x01;
constexpr uint8_t MCP_GPIOA  = 0x12;
constexpr uint8_t MCP_GPIOB  = 0x13;
constexpr uint8_t MCP_OLATA  = 0x14;
constexpr uint8_t MCP_OLATB  = 0x15;

TwoWire I2Cext = TwoWire(1);
bool mcpPresent = false;

void mcpWrite(uint8_t reg, uint8_t val) {
    I2Cext.beginTransmission(MCP23017_ADDR);
    I2Cext.write(reg);
    I2Cext.write(val);
    I2Cext.endTransmission();
}

// ---------- OLED ----------
Adafruit_SSD1306 oled(128, 64, &Wire, PIN_OLED_RST);

// ---------- WS2812B chain ----------
Adafruit_NeoPixel strip(NUM_PIXELS, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);

// ---------- Panel state ----------
struct State {
    uint8_t activeRadio    = 1;     // 1 or 2
    uint8_t bandIdx        = 0;     // 0..7
    bool    ptt            = false; // not driven yet - reserved for milestone 4
    bool    relayActiveLow = true;  // most cheap modules are active-low
};
State g;

const char* BAND_NAMES[8] = {
    "160m", "80m", "40m", "20m", "15m", "10m", "WARC", "BYP"
};

// Logical -> physical translation. setRelays(0x01) always means "relay 1 on"
// regardless of the module's polarity; we mask/invert here.
void setRelays(uint8_t mask) {
    if (!mcpPresent) return;
    uint8_t phys = g.relayActiveLow ? (uint8_t)~mask : mask;
    mcpWrite(MCP_OLATB, phys);
}

// ---------- Rendering ----------
void drawPanel() {
    oled.clearDisplay();
    oled.setTextColor(SSD1306_WHITE);
    oled.setTextSize(2);
    oled.setCursor(0, 0);
    oled.printf("RIG%d %s", g.activeRadio, BAND_NAMES[g.bandIdx]);
    oled.setTextSize(1);
    oled.setCursor(0, 24);
    oled.print(g.ptt ? "PTT" : "RX ");
    oled.setCursor(0, 38);
    oled.printf("polarity: active-%s", g.relayActiveLow ? "low" : "high");
    oled.setCursor(0, 50);
    oled.print(mcpPresent ? "MCP23017: OK" : "MCP23017: not found");
    oled.display();
}

void drawLeds() {
    // 0: active radio (bright white = R1, dim white = R2)
    strip.setPixelColor(0, g.activeRadio == 1 ? strip.Color(255, 255, 255)
                                              : strip.Color(40,  40,  40));
    // 1: PTT (red when keyed)
    strip.setPixelColor(1, g.ptt ? strip.Color(255, 0, 0) : 0);
    // 2-3: band group
    uint32_t c;
    if      (g.bandIdx <= 1) c = strip.Color(0,   0,   255);  // low (160/80)
    else if (g.bandIdx <= 5) c = strip.Color(0,   255, 0);    // mid (40-10)
    else                     c = strip.Color(255, 128, 0);    // WARC/bypass
    strip.setPixelColor(2, c);
    strip.setPixelColor(3, c);
    strip.show();
}

// ---------- Buttons (debounced polling) ----------
constexpr uint32_t DEBOUNCE_MS = 30;
uint32_t btnLastEdge[4] = {0};
bool     btnPrev[4]     = {true, true, true, true};

void onButtonPress(int i) {
    switch (i) {
        case 0: g.activeRadio = 1; break;
        case 1: g.activeRadio = 2; break;
        case 2: g.bandIdx = (g.bandIdx + 7) % 8; break;
        case 3: g.bandIdx = (g.bandIdx + 1) % 8; break;
    }
    setRelays((uint8_t)(1u << g.bandIdx));
    drawPanel();
    drawLeds();
    Serial.printf("[btn %d] RIG %d  band %s\n",
                  i + 1, g.activeRadio, BAND_NAMES[g.bandIdx]);
}

void pollButtons() {
    uint32_t now = millis();
    for (int i = 0; i < 4; i++) {
        bool pressed = (digitalRead(PIN_BUTTON[i]) == LOW);
        if (pressed != btnPrev[i] && (now - btnLastEdge[i]) > DEBOUNCE_MS) {
            btnLastEdge[i] = now;
            btnPrev[i]     = pressed;
            if (pressed) onButtonPress(i);
        }
    }
}

// ---------- Serial REPL ----------
void cmdHelp() {
    Serial.println(F("commands:"));
    Serial.println(F("  ?           this help"));
    Serial.println(F("  scan        I2C scan on the external bus"));
    Serial.println(F("  walk        walking-bit across all 8 relays (200 ms each)"));
    Serial.println(F("  tst <0-7>   energise one relay (logical bit)"));
    Serial.println(F("  pol         polarity-check helper"));
    Serial.println(F("  inv         flip the active-low / active-high flag"));
    Serial.println(F("  off         release all relays"));
}

void cmdScan() {
    Serial.println(F("I2C scan @ external bus (GPIO 41/42):"));
    int n = 0;
    for (uint8_t addr = 1; addr < 127; addr++) {
        I2Cext.beginTransmission(addr);
        if (I2Cext.endTransmission() == 0) {
            Serial.printf("  found 0x%02X\n", addr);
            n++;
        }
    }
    Serial.printf("done. %d device(s).\n", n);
}

void cmdWalk() {
    if (!mcpPresent) { Serial.println(F("MCP23017 not present.")); return; }
    Serial.println(F("walking bit..."));
    for (int i = 0; i < 8; i++) {
        setRelays((uint8_t)(1u << i));
        Serial.printf("  bit %d\n", i);
        delay(200);
    }
    setRelays(0x00);
    Serial.println(F("done."));
}

void cmdTst(int i) {
    if (!mcpPresent) { Serial.println(F("MCP23017 not present.")); return; }
    if (i < 0 || i > 7) { Serial.println(F("bit must be 0..7")); return; }
    setRelays((uint8_t)(1u << i));
    Serial.printf("relay %d ON (polarity %s)\n",
                  i, g.relayActiveLow ? "active-low" : "active-high");
}

void cmdPol() {
    if (!mcpPresent) { Serial.println(F("MCP23017 not present.")); return; }
    Serial.println(F("polarity check:"));
    Serial.println(F("  writing 0x01 with current polarity assumption"));
    Serial.printf("  current flag: active-%s\n",
                  g.relayActiveLow ? "low" : "high");
    setRelays(0x01);
    Serial.println(F("  -> RELAY 1 should be the only one energised."));
    Serial.println(F("  -> if instead R2..R8 are all on, run 'inv' to flip."));
}

void cmdInv() {
    g.relayActiveLow = !g.relayActiveLow;
    Serial.printf("polarity flag now active-%s\n",
                  g.relayActiveLow ? "low" : "high");
    setRelays(0x00);
    drawPanel();
}

void cmdOff() {
    setRelays(0x00);
    Serial.println(F("all relays released."));
}

String inbuf;
void handleLine(String line) {
    line.trim();
    if      (line == "?" || line == "help") cmdHelp();
    else if (line == "scan")                cmdScan();
    else if (line == "walk")                cmdWalk();
    else if (line.startsWith("tst "))       cmdTst(line.substring(4).toInt());
    else if (line == "pol")                 cmdPol();
    else if (line == "inv")                 cmdInv();
    else if (line == "off")                 cmdOff();
    else if (line.length() > 0)
        Serial.println(F("unknown command. type '?' for help."));
}

// ---------- Setup ----------
void setup() {
    // Hold SX1262 in reset BEFORE anything else (REVIEW: stops the LoRa
    // modem from emitting on 868/915 MHz at power-up if firmware never
    // configures it).
    pinMode(PIN_LORA_RST, OUTPUT);
    digitalWrite(PIN_LORA_RST, LOW);

    // Enable Vext rail (powers the OLED on most Heltec V3 revs).
    pinMode(PIN_VEXT, OUTPUT);
    digitalWrite(PIN_VEXT, LOW);
    delay(50);

    Serial.begin(115200);
    delay(300);
    Serial.println();
    Serial.println(F("SO2R Box POC firmware boot"));
    Serial.println(F("type '?' for serial commands"));

    // OLED on Wire (primary I2C)
    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL, 400000);
    if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
        Serial.println(F("OLED init failed - check Vext / I2C pins"));
    } else {
        oled.clearDisplay();
        oled.setTextColor(SSD1306_WHITE);
        oled.setTextSize(1);
        oled.setCursor(0, 0);
        oled.println(F("SO2R POC boot..."));
        oled.display();
    }

    // Buttons
    for (int i = 0; i < 4; i++) pinMode(PIN_BUTTON[i], INPUT_PULLUP);

    // WS2812B chain
    strip.begin();
    strip.setBrightness(40);  // keep current draw modest off the USB rail
    strip.clear();
    strip.show();

    // External I2C bus for MCP23017
    I2Cext.begin(PIN_SDA_EXT, PIN_SCL_EXT, 100000);
    I2Cext.beginTransmission(MCP23017_ADDR);
    if (I2Cext.endTransmission() == 0) {
        mcpPresent = true;
        Serial.printf("MCP23017 found at 0x%02X\n", MCP23017_ADDR);
        mcpWrite(MCP_IODIRB, 0x00);  // GPB = outputs
        setRelays(0x00);             // release everything regardless of polarity
    } else {
        Serial.println(F("MCP23017 NOT found - milestone 1/3 still work; relay cmds disabled"));
    }

    drawPanel();
    drawLeds();
}

void loop() {
    while (Serial.available()) {
        char c = (char)Serial.read();
        if (c == '\n' || c == '\r') {
            if (inbuf.length() > 0) { handleLine(inbuf); inbuf = ""; }
        } else {
            inbuf += c;
        }
    }
    pollButtons();
    delay(2);
}
