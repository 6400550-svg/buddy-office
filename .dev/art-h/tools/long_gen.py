#!/usr/bin/env python3
# 长发的「蒙版 + 涂色」生成器：边缘用区间描述，涂色 = 左缘亮 + 右缘暗 + 高光带 + 发丝线
import os,sys
SP=os.environ.get('SP','/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad/hs')

def mask_text(edges, notches=None):
    """edges: {y:(xL,xR) 或 [(xL,xR),...]}；notches: {y:[x,...]} 挖掉的格子"""
    out=[]
    for y in sorted(edges):
        segs=edges[y]
        if isinstance(segs,tuple): segs=[segs]
        for (a,b) in segs:
            s=['#']*(b-a+1)
            for x in (notches or {}).get(y,[]):
                if a<=x<=b: s[x-a]='.'
            out.append(f'        {y}@{a}| '+''.join(s))
    return '\n'.join(out)

def is_boundary(edges,x,y):
    def has(xx,yy):
        segs=edges.get(yy)
        if segs is None: return False
        if isinstance(segs,tuple): segs=[segs]
        return any(a<=xx<=b for a,b in segs)
    return has(x,y) and not (has(x-1,y) and has(x+1,y) and has(x,y-1) and has(x,y+1))

def interior_rows(edges):
    """返回 {y:[x,...]} 内部（非轮廓）像素"""
    out={}
    for y,segs in edges.items():
        if isinstance(segs,tuple): segs=[segs]
        xs=[]
        for a,b in segs:
            for x in range(a,b+1):
                if not is_boundary(edges,x,y): xs.append(x)
        out[y]=xs
    return out

def detail_text(paint):
    rows={}
    for (x,y),c in paint.items(): rows.setdefault(y,{})[x]=c
    out=[]
    for y in sorted(rows):
        xs=sorted(rows[y]); seg=[xs[0]]; segs=[]
        for x in xs[1:]:
            if x==seg[-1]+1: seg.append(x)
            else: segs.append(seg); seg=[x]
        segs.append(seg)
        for s in segs: out.append(f'        {y}@{s[0]}| '+''.join(rows[y][x] for x in s))
    return '\n'.join(out)
