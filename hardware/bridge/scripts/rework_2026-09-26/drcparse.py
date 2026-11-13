import sys,re,collections
txt=open(sys.argv[1]).read()
skip=set(sys.argv[2].split(',')) if len(sys.argv)>2 else set()
entries=re.split(r'\n(?=\[)', txt)
seen=collections.Counter(); order=[]
for e in entries:
    m=re.match(r'\[(\w+)\]: (.*)', e)
    if not m or m.group(1) in skip: continue
    items=[re.sub(r'\s+',' ',l.strip()) for l in e.split('\n') if l.strip().startswith('@')]
    key=(m.group(1), ' || '.join(items))
    if key not in seen: order.append(key)
    seen[key]+=1
for k in order: print(f"{seen[k]:2}x [{k[0]}] {k[1]}")
