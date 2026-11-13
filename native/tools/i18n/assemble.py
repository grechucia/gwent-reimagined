import json, re, glob, os, sys
H = os.path.dirname(os.path.abspath(__file__)); N = os.path.dirname(os.path.dirname(H)); D = N + '/Resources/data'
en = json.load(open(D + '/lang_en.json', encoding='utf-8'))
def strip(h):
    t = h.replace('<br>', '\n'); t = re.sub('<[^>]+>', '', t)
    for e, r in [('&amp;','&'),('&quot;','"'),('&#39;',"'"),('&lt;','<'),('&gt;','>'),('&nbsp;',' ')]: t = t.replace(e, r)
    return t.strip()
codes = sys.argv[1:] or sorted({os.path.basename(p).split('_')[1] for p in glob.glob(H + '/tr_*_*.json')})
src = json.load(open(H + '/source_en.json', encoding='utf-8'))
for code in codes:
    tr = {}
    for p in sorted(glob.glob(H + '/src_*.json')):
        i = p[:-5].rsplit('_', 1)[1]; q = H + f'/tr_{code}_{i}.json'
        if not os.path.exists(q): continue
        a, b = json.load(open(p, encoding='utf-8')), json.load(open(q, encoding='utf-8'))
        if len(a) != len(b): print(f'! {code} part {i}: {len(b)} instead of {len(a)}'); continue
        tr.update({x: y for x, y in zip(a, b) if y})
    t = lambda s: tr.get(s) or s
    missing = [s for s in src if s not in tr]
    out = {'name': code,
           'cards': {k: {kk: t(vv) for kk, vv in v.items()} for k, v in en['cards'].items()},
           'abilities': {k: {kk: t(vv) for kk, vv in v.items()} for k, v in en['abilities'].items()},
           'factions': {k: {kk: t(vv) for kk, vv in v.items()} for k, v in en['factions'].items()},
           'ui': {s: t(s) for s in list(en['ui']) + src},
           'blocks': {k: t(strip(h)) for k, h in en['blocks'].items() if strip(h)}}
    json.dump(out, open(D + f'/lang_{code}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1, sort_keys=True)
    print(f'lang_{code}.json: {len(src) - len(missing)}/{len(src)} translated')
