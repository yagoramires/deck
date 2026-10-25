import re,subprocess,sys
funcs=sys.argv[1:]
for f in funcs:
    out=subprocess.run(['otool','-tV','-arch','arm64','sdlib.arm64','-p',f],capture_output=True,text=True).stdout
    # stop at next symbol label after the first
    lines=out.splitlines()[3:]
    body=[]
    for l in lines:
        if re.match(r'^__Z',l): break
        body.append(l)
    regs={}; bytes_={}; calls=[]
    for l in body:
        m=re.search(r'\tmov\tw(\d+), #(0x[0-9a-f]+|\d+)$',l)
        if m: regs[m.group(1)]=int(m.group(2),0); continue
        m=re.search(r'\tstrb\tw(\d+|zr), \[x8(?:, #(0x[0-9a-f]+))?\]',l)
        if m:
            off=int(m.group(2) or '0',0); r=m.group(1)
            v = 0 if r=='zr' else regs.get(r,'?')
            bytes_.setdefault(off,[]).append(v); continue
        m=re.search(r'; symbol stub for: (\S+)',l)
        if m and 'realloc' not in m.group(1): calls.append(m.group(1))
    s=' '.join(f"{o}:{','.join((chr(x) if isinstance(x,int) and 32<x<127 else hex(x) if isinstance(x,int) else x) for x in v)}" for o,v in sorted(bytes_.items()))
    name=subprocess.run(['c++filt',f],capture_output=True,text=True).stdout.strip()
    print(f"== {name}\n   {s}")
