import json,glob,sys
for q in sorted(glob.glob('tr_*_*.json')):
    i=q[:-5].rsplit('_',1)[1]
    try: b=json.load(open(q,encoding='utf-8'))
    except Exception as e: print(q,'JSON ERROR',e); continue
    a=json.load(open(f'src_{i}.json',encoding='utf-8'))
    if len(a)!=len(b): print(q,len(b),'!=',len(a))
print('ok')
