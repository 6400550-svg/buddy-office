#!/usr/bin/env python3
# 生成 styles/curly.swift：手画轮廓 + 「小团卷」画家算法上色（右下的先画、左上的后画盖在上面）。
import math, os, sys, random
SP=os.environ.get('SP','/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad/hs')

def parse(rows, y0, x0=-2):
    m=set()
    for j,l in enumerate(rows):
        for i,c in enumerate(l):
            if c not in '. ': m.add((x0+i,y0+j))
    return m

def boundary(m,x,y):
    return (x,y) in m and any(((x+dx,y+dy) not in m) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)))

def paint(mask, curls, hi_t=-0.42, sh_t=0.30, rim=0.95):
    """curls: [(cx,cy,r)] 顺序 = 先画→后画（后画的盖在上面）。返回 {(x,y):char}，只画内部（非轮廓）像素。"""
    out={}
    for (cx,cy,r) in curls:
        for (x,y) in mask:
            if boundary(mask,x,y): continue
            px,py=x+0.5,y+0.5
            d=math.hypot(px-cx,py-cy)
            if d>r: continue
            t=((px-cx)+(py-cy))/(r*2**0.5)          # −1 左上 … +1 右下
            if t>sh_t: ch='g'
            elif t<hi_t and d>r*0.35: ch='h'
            else: ch='H'
            out[(x,y)]=ch
    return out

def lattice(x0,x1,y0,y1,dx=3.0,dy=2.6,r=2.3,jit=0.0,seed=1):
    rnd=random.Random(seed)
    cs=[]
    row=0
    y=y0
    while y<=y1:
        x=x0+(dx/2 if row%2 else 0)
        while x<=x1:
            cs.append((x+rnd.uniform(-jit,jit),y+rnd.uniform(-jit,jit),r))
            x+=dx
        y+=dy; row+=1
    # 右下先画、左上后画
    cs.sort(key=lambda c:-(c[0]+c[1]))
    return cs

def emit_mask(rows,y0,x0=-2):
    out=[]
    for j,l in enumerate(rows):
        s=l.rstrip('.')
        lead=len(l)-len(l.lstrip('.'))
        if not s.strip('.'): continue
        out.append(f'        {y0+j}@{x0+lead}| {l.strip(".")}')
    return '\n'.join(out)

def emit_detail(det, mask):
    rows={}
    for (x,y),c in det.items(): rows.setdefault(y,{})[x]=c
    out=[]
    for y in sorted(rows):
        xs=sorted(rows[y])
        # 连续段输出
        seg=[xs[0]]; segs=[]
        for x in xs[1:]:
            if x==seg[-1]+1: seg.append(x)
            else: segs.append(seg); seg=[x]
        segs.append(seg)
        for s in segs:
            out.append(f'        {y}@{s[0]}| '+''.join(rows[y][x] for x in s))
    return '\n'.join(out)

def voronoi_seeds(mask, n, seed=1, iters=4):
    """在 mask 的内部像素里撒 n 个种子，Lloyd 松弛几次让它们均匀。"""
    rnd=random.Random(seed)
    inner=[(x,y) for (x,y) in mask if not boundary(mask,x,y)]
    seeds=[rnd.choice(inner) for _ in range(n)]
    seeds=[(x+0.5,y+0.5) for x,y in seeds]
    for _ in range(iters):
        cells={i:[] for i in range(n)}
        for (x,y) in inner:
            px,py=x+0.5,y+0.5
            k=min(range(n),key=lambda i:(px-seeds[i][0])**2+(py-seeds[i][1])**2)
            cells[k].append((px,py))
        for i in range(n):
            if cells[i]:
                seeds[i]=(sum(p[0] for p in cells[i])/len(cells[i]),sum(p[1] for p in cells[i])/len(cells[i]))
    return seeds

def voronoi_paint(mask, seeds, hi_t=-0.55, sh_t=0.5, crease=True, hi_nb=True):
    inner=[(x,y) for (x,y) in mask if not boundary(mask,x,y)]
    n=len(seeds)
    owner={}
    for (x,y) in inner:
        px,py=x+0.5,y+0.5
        owner[(x,y)]=min(range(n),key=lambda i:(px-seeds[i][0])**2+(py-seeds[i][1])**2)
    cells={}
    for p,k in owner.items(): cells.setdefault(k,[]).append(p)
    cent={k:(sum(x+0.5 for x,_ in ps)/len(ps),sum(y+0.5 for _,y in ps)/len(ps)) for k,ps in cells.items()}
    rad={k:max(1.0,max(math.hypot(x+0.5-cent[k][0],y+0.5-cent[k][1]) for x,y in ps)) for k,ps in cells.items()}
    out={}
    for (x,y),k in owner.items():
        cx,cy=cent[k]
        t=((x+0.5-cx)+(y+0.5-cy))/(rad[k]*2**0.5)
        ch='H'
        if t<hi_t: ch='h'
        elif t>sh_t: ch='g'
        if crease:
            # 贴着右/下邻居的边 = 这个团的右下边缘 → 暗
            for dx,dy in ((1,0),(0,1)):
                q=(x+dx,y+dy)
                if q in owner and owner[q]!=k: ch='g'
            # 贴着左/上邻居的边 = 左上边缘 → 亮一点
            for dx,dy in ((-1,0),(0,-1)):
                q=(x+dx,y+dy)
                if hi_nb and q in owner and owner[q]!=k and ch=='H': ch='h'
        out[(x,y)]=ch
    return out
