//! Compiles a `cw-domain` `ParsedQuery` to SQL against the `qso`/`service_presence`
//! schema, at parity with the Swift `QueryCompiler`. See
//! docs/plans/2026-06-15-qso-cutover-B-query-compiler-design.md.

pub mod compiler;
pub mod sql;

pub use compiler::compile_where;
