use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser)]
struct Cli {
    #[arg(long)]
    schema: PathBuf,
    #[arg(long)]
    swift_out: PathBuf,
    #[arg(long)]
    rust_out: PathBuf,
    #[arg(long)]
    check: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let schema = macro_codegen::schema::StepSchema::load(&cli.schema)?;
    let swift = macro_codegen::swift_emit::emit(&schema)?;
    let rust = macro_codegen::rust_emit::emit(&schema)?;
    if cli.check {
        compare_or_fail(&cli.swift_out, &swift, "swift")?;
        compare_or_fail(&cli.rust_out, &rust, "rust")?;
        println!("generated files up-to-date");
    } else {
        std::fs::write(&cli.swift_out, swift)?;
        std::fs::write(&cli.rust_out, rust)?;
        println!("wrote {} and {}", cli.swift_out.display(), cli.rust_out.display());
    }
    Ok(())
}

fn compare_or_fail(path: &std::path::Path, expected: &str, lang: &str) -> Result<()> {
    let actual = std::fs::read_to_string(path)
        .map_err(|e| anyhow::anyhow!("missing {} output at {}: {}", lang, path.display(), e))?;
    if actual == expected {
        return Ok(());
    }
    let mut diff_lines: Vec<String> = Vec::new();
    let actual_lines: Vec<&str> = actual.lines().collect();
    let expected_lines: Vec<&str> = expected.lines().collect();
    let n = std::cmp::max(actual_lines.len(), expected_lines.len());
    let mut shown = 0;
    for i in 0..n {
        let a = actual_lines.get(i).copied().unwrap_or("<EOF>");
        let e = expected_lines.get(i).copied().unwrap_or("<EOF>");
        if a != e {
            diff_lines.push(format!("  line {}: actual = {:?}", i + 1, a));
            diff_lines.push(format!("           expected = {:?}", e));
            shown += 1;
            if shown >= 5 {
                break;
            }
        }
    }
    anyhow::bail!(
        "{} generated file is stale at {}.\nFirst differing lines:\n{}\n\nRegenerate with `cargo run -- --schema <…> --swift-out <…> --rust-out <…>` (without --check).",
        lang, path.display(), diff_lines.join("\n")
    )
}
