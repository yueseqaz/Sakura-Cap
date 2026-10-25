# Vendored libwebp

Version: 1.6.0 (unmodified upstream C sources).

Source archive:
https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz

SHA-256:
e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564

The checksum is also published in the Homebrew webp 1.6.0 formula.
Retained files: `.c` and `.h` files from `src/dec`, `src/dsp`, `src/enc`,
`src/utils`, `src/webp`, and `sharpyuv`; plus COPYING, PATENTS, and AUTHORS.
`include/module.modulemap` is the local Swift interoperability shim.

SwiftPM builds this code into the app statically. Neither Homebrew, cwebp,
network access, nor a separately installed dynamic library is needed at runtime
or when building this source tree. Upstream's optional image-file parsers, command
line tools, mux/demux libraries, and examples are not included.

Preserve COPYING and PATENTS when updating. Re-check upstream security releases
before updating the source archive and digest. The app bundle includes the
license notices under Resources/ThirdParty/libwebp.
