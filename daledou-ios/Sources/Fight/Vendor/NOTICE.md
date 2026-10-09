# Vendored compression code

- `BitByteData/` — https://github.com/tsolomko/BitByteData (MIT)
- `SWCompression/LZMA` + minimal Common — https://github.com/tsolomko/SWCompression (MIT)

Used only to inflate SWF ZWS→FWS in the app process before WKWebView loads `action_gg`, so WebContent avoids LZMA decompress peak.
