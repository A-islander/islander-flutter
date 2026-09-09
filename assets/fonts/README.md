# Islander UI font subset

`islander-ui.otf` is a generated UI-text subset of Noto Sans CJK SC Regular
from https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/SimplifiedChinese.
It retains the original copyright metadata and is distributed under the
included SIL Open Font License 1.1 (`OFL.txt`). It is not a complete CJK font.

Used as the Web UI font to avoid missing interface glyphs when remote font
fallback is unavailable. Native platforms retain their existing system font.
New text not covered by the subset continues to use the existing fallbacks.

Regenerate from an upstream `NotoSansCJKsc-Regular.otf` with fonttools:

```sh
rg --no-filename '.' lib --glob '*.dart' | uv tool run --from fonttools pyftsubset /path/to/NotoSansCJKsc-Regular.otf --text-file=/dev/stdin --unicodes=U+0000-00FF,U+2000-206F,U+3000-303F --name-IDs='*' --output-file=assets/fonts/islander-ui.otf
```
