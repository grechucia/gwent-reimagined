import json, os, glob
H = os.path.dirname(os.path.abspath(__file__))
src = json.load(open(H + '/source_en.json', encoding='utf-8'))
old = sorted(glob.glob(H + '/src_*.json'), key=lambda p: int(p[:-5].rsplit('_', 1)[1]))
have = set()
for p in old: have |= set(json.load(open(p, encoding='utf-8')))
new = [s for s in src if s not in have]
if new:
    json.dump(new, open(H + f'/src_{len(old)}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print('parts:', len(old), '+ new strings:', len(new))
