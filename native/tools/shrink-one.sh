#!/bin/sh
src="$1/$3"; dst="$2/$3"
h=$(sips -g pixelHeight "$src" 2>/dev/null | awk '/pixelHeight/{print $2}')
if [ "${h:-0}" -gt 900 ]; then
  sips -Z 900 "$src" --out "$dst" >/dev/null 2>&1 || cp "$src" "$dst"
else
  cp "$src" "$dst"
fi
