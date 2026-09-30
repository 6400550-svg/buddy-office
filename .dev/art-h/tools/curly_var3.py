import os,sys,math,random
from curly_gen import *
from curly_design import BACK,Q34BACK,SIDE,FRONT,Q34FRONT,Y0
SP=os.environ['SP']
def paint3(mask, seeds, hi_t=-0.5, sh_t=0.55, drop=0.35, seed=1):
    rnd=random.Random(seed)
    inner=[(x,y) for (x,y) in mask if not boundary(mask,x,y)]
    n=len(seeds); owner={}
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
        edge=False
        for dx,dy in ((1,0),(0,1)):
            q=(x+dx,y+dy)
            if q in owner and owner[q]!=k: edge=True
        if edge and rnd.random()>drop: ch='g'
        out[(x,y)]=ch
    # despeckle
    res=dict(out)
    for (x,y),c in out.items():
        if c=='H': continue
        if not any(out.get((x+dx,y+dy))==c for dx,dy in ((1,0),(-1,0),(0,1),(0,-1))): res[(x,y)]='H'
    return res
def blk(style,facing,rows,seeds,**kw):
    m=parse(rows,Y0); det=paint3(m,seeds,**kw)
    return f'''        addHairFull(book, "{style}", .{facing}, mask: """
{emit_mask(rows,Y0)}
        """, detail: """
{emit_detail(det,m)}
        """)
'''
