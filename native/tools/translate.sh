#!/bin/zsh
set -e
HERE=${0:A:h}
NATIVE=${HERE:h}
DATA=$NATIVE/Resources/data
BIN=$NATIVE/build/.translate
mkdir -p $NATIVE/build
python3 - "$NATIVE/Sources" "$DATA/ui_extra_en.json" <<'PY'
import re, sys, json, glob
out = set()
for f in glob.glob(sys.argv[1] + "/*.swift"):
    s = open(f, encoding="utf-8").read()
    for m in re.finditer(r'L2\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)', s): out.add(m.group(2))
    for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"\)', s): out.add(m.group(1))
json.dump(sorted(x for x in out if x.strip()), open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
print("» teksty z kodu:", len(out))
PY
xcrun swiftc -O -parse-as-library $HERE/translate.swift -o $BIN
langs=("$@"); (( $#langs )) || langs=(fr it de es zh ja ko pt ru)
$BIN $DATA $langs
