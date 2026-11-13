# Macro opcode tables

This directory holds protocol-specific opcode tables consumed by
`RadioMacroOpcodeTable` for `.rawBytes` capability inference inside
`MacroVerifier`. Each file maps a per-protocol opcode pattern to the set
of `RadioMacroCapabilities` bits it should imply. The literal token `??`
is a wildcard byte — only the position is matched, not the value.
Matching is substring/window-based: the parser slides the masked
pattern across the raw-bytes payload, so framing bytes (CI-V preamble,
controller address, etc.) do not have to be encoded. Update these tables
whenever a CAT command's capability changes upstream — e.g. a vendor adds
a new PTT opcode, or a power-level command moves to a different
subaddress — and keep the `$comment` and per-entry `comment` fields
truthful so reviewers can audit the security-relevant inference path.
