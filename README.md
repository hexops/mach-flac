# mach-flac: FLAC audio encoding/decoding for Zig

Zig bindings to `libflac` - the battle-hardened official xiph.org C library for FLAC audio encoding & decoding. Features:

* Zero-fuss installation, cross compilation, and no system dependencies.
* Encoding & decoding support

## Usage

```
zig build test
ffplay -f s32le -ar 48000 -ac 2 zig-out/decode_output.pcm
```

See https://machengine.org/pkg/mach-flac

## Issues

Issues are tracked in the [main Mach repository](https://github.com/hexops/mach/issues?q=is%3Aissue+is%3Aopen+label%3Aflac).

## Community

Join the Mach engine community [on Discord](https://discord.gg/XNG3NZgCqp) to discuss this project, ask questions, get help, etc.
