//! Wires up the ESP-IDF environment (embuild). No C sources — the sat
//! bridge has no FT8 codec.

fn main() {
    embuild::espidf::sysenv::output();
}
