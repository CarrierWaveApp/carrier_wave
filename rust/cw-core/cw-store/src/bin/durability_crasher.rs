//! Spawned by the durability suite to test app-crash durability on the REAL
//! syscall path: upsert, ack, then abort() with no clean shutdown.
use std::io::Write;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (db, key, id) = (&args[1], &args[2], &args[3]);
    let store = cw_store::Store::open(db, key).expect("open");
    let mut qso = cw_store::testing::sample_qso_min(id);
    qso.qso_date = 1000;
    store.upsert_qso(&qso).expect("upsert");
    let mut out = std::io::stdout();
    writeln!(out, "ACK {id}").unwrap();
    out.flush().unwrap();
    std::process::abort();
}
