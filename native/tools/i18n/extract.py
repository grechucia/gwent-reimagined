import json, re, glob, os, sys
H = os.path.dirname(os.path.abspath(__file__)); N = os.path.dirname(os.path.dirname(H))
d = json.load(open(N + '/Resources/data/lang_en.json', encoding='utf-8'))
def strip(h):
    t = h.replace('<br>', '\n'); t = re.sub('<[^>]+>', '', t)
    for e, r in [('&amp;','&'),('&quot;','"'),('&#39;',"'"),('&lt;','<'),('&gt;','>'),('&nbsp;',' ')]: t = t.replace(e, r)
    return t.strip()
texts = set()
for v in d['cards'].values():
    for k in ('name', 'quote'):
        if v.get(k): texts.add(v[k])
for grp in ('abilities', 'factions'):
    for v in d[grp].values(): texts |= {x for x in v.values() if x}
texts |= {k for k in d['ui'] if k.strip()}
texts |= {strip(h) for h in d['blocks'].values() if strip(h)}
for f in glob.glob(N + '/Sources/*.swift'):
    s = open(f, encoding='utf-8').read()
    for m in re.finditer(r'L2\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)', s): texts.add(m.group(2))
    for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"\)', s): texts.add(m.group(1))
lst = sorted(t for t in texts if t.strip())
json.dump(lst, open(H + '/source_en.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print(len(lst), sum(map(len, lst)))
