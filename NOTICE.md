# Third-party notices

kooky bundles or links the following third-party projects. Each retains its
upstream license; nothing here is dual-licensed under kooky's MIT.

## Bundled in the source tree

### Onest (font)
- Source: <https://github.com/google/fonts/tree/main/ofl/onest>
- Designer: Martín Sznaider, Indian Type Foundry
- License: SIL Open Font License 1.1
- File: `Sources/KookyKit/Resources/Fonts/Onest.ttf`

### JetBrains Mono (font)
- Source: <https://github.com/JetBrains/JetBrainsMono>
- License: SIL Open Font License 1.1
- File: `Sources/KookyKit/Resources/Fonts/JetBrainsMono-Regular.ttf`

### lobe-icons (brand PNGs)
- Source: <https://github.com/lobehub/lobe-icons>
- License: MIT
- Files: `Sources/KookyKit/Resources/Icons/{claudecode,codex,gemini,opencode,amp}.png`

## Pulled at build time

### libghostty
- Source: <https://github.com/ghostty-org/ghostty>
- License: MIT
- Distribution: prebuilt `GhosttyKit.xcframework` fetched by `scripts/setup-libghostty.sh` into `Vendor/` (gitignored)

