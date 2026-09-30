#!/usr/bin/env python3
"""发型设计小库：蒙版（带标签的行）+ 涂色操作 → Swift 的 addHairFull 文本。
坐标全是头盒子坐标。涂色默认只动内部（非轮廓）像素；force=True 才动轮廓。"""
import math, os, re

def parse_rows(text, x0=0, y0=0):
    """解析 `y@x| chars` / `y| chars` 行 → {(x,y): char}"""
    out={}; y=y0
    for raw in text.strip('\n').split('\n'):
        line=raw.strip()
        if not line: continue
        x=x0; body=line
        if '|' in line:
            head,body=line.split('|',1); body=body.strip(); head=head.strip()
            parts=head.split('@')
            y=int(parts[0])
            if len(parts)>1: x=int(parts[1])
        for i,c in enumerate(body):
            out[(x+i,y)]=c
        y+=1
    return out

class Spr:
    def __init__(self, style, facing, mask_text, x0=0, y0=0, note=None):
        self.style=style; self.facing=facing; self.note=note
        self.mask_text=mask_text.strip('\n')
        cells=parse_rows(mask_text,x0,y0)
        self.mask={p for p,c in cells.items() if c not in '. '}
        self.paint={}
    def has(self,x,y): return (x,y) in self.mask
    def boundary(self,x,y):
        return self.has(x,y) and not (self.has(x-1,y) and self.has(x+1,y) and self.has(x,y-1) and self.has(x,y+1))
    def put(self,x,y,c,force=False,free=False):
        if free: self.paint[(x,y)]=c; return
        if not self.has(x,y): return
        if self.boundary(x,y) and not force: return
        self.paint[(x,y)]=c
    def pts(self,pts,c,force=False):
        for (x,y) in pts: self.put(x,y,c,force)
    def stamp(self,text,x0=0,y0=0,force=False,free=False):
        """带标签的行；'.' 不动。free=True：允许画在蒙版之外（比如刘海在额头上的投影用肤色阴影 j）"""
        for (x,y),c in parse_rows(text,x0,y0).items():
            if c=='.': continue
            self.put(x,y,c,force,free)
    def emit(self, indent='        '):
        # mask
        det={}
        for (x,y),c in self.paint.items(): det.setdefault(y,{})[x]=c
        lines=[]
        for y in sorted(det):
            xs=sorted(det[y]); seg=[xs[0]]; segs=[]
            for x in xs[1:]:
                if x==seg[-1]+1: seg.append(x)
                else: segs.append(seg); seg=[x]
            segs.append(seg)
            for s in segs: lines.append(f'{indent}{y}@{s[0]}| '+''.join(det[y][x] for x in s))
        mask=''.join(indent+l.strip()+'\n' for l in self.mask_text.split('\n'))
        d=''.join(l+'\n' for l in lines)
        fac={'back':'back','q34back':'threeQuarterBack','side':'side','q34front':'threeQuarterFront','front':'front'}[self.facing]
        s=(f'{indent[:-4]}// {self.note}\n' if self.note else '')+f'{indent[:-4]}addHairFull(book, "{self.style}", .{fac}, mask: """\n{mask}{indent}"""'
        if lines: s+=f', detail: """\n{d}{indent}"""'
        s+=')\n'
        return s

def meridian(cx, y_top, y_bot, A, y_from=None, y_to=None):
    """球面上的经线：在 y_top（极点）和 y_bot（另一个极点）收拢，中间向外鼓出 A 个像素。返回 [(x,y)]"""
    pts=[]
    y_from=y_top if y_from is None else y_from
    y_to=y_bot if y_to is None else y_to
    for y in range(int(math.ceil(y_from)), int(math.floor(y_to))+1):
        t=(y+0.5-y_top)/(y_bot-y_top)
        if t<0 or t>1: continue
        x=cx+A*math.sin(math.pi*t)
        pts.append((int(math.floor(x)),y))
    return pts

def mask_from_ranges(spec, notches=None):
    """spec: {y: (x0,x1) 或 [(x0,x1),...]} → 带标签的 mask 文本"""
    out=[]
    for y in sorted(spec):
        segs=spec[y]
        if isinstance(segs,tuple): segs=[segs]
        for a,b in segs:
            s=['#']*(b-a+1)
            for x in (notches or {}).get(y,[]):
                if a<=x<=b: s[x-a]='.'
            out.append(f'{y}@{a}| '+''.join(s))
    return '\n'.join(out)

def write_style(path, fn, comment, sprites):
    txt=f'    // ============ {comment} ============\n    static func {fn}(_ book: SpriteBook) {{\n'
    txt+=''.join(s.emit() for s in sprites)
    txt+='    }\n'
    open(path,'w').write(txt)

def disk(cx, cy, r):
    """圆盘覆盖的像素（连续坐标，像素中心 x+0.5）"""
    out=set()
    for y in range(int(cy-r-1), int(cy+r+2)):
        for x in range(int(cx-r-1), int(cx+r+2)):
            if (x+0.5-cx)**2+(y+0.5-cy)**2<=r*r: out.add((x,y))
    return out

def sphere_part(s, pixels, hi_t=-0.5, sh_t=0.45, internal=True, ring=True):
    """把一块 pixels（球/团子/马尾）当作叠在头发上的一个独立物体来涂色：
    · 内部：左上亮、右下暗；
    · 边缘：贴着「别的头发」的右/下边缘画最深描边(1)，左/上边缘画阴影(g)——和 ShadeKit 对整张蒙版做的一样，只是这里是内部的物体边缘。"""
    xs=[x for x,_ in pixels]; ys=[y for _,y in pixels]
    cx=(min(xs)+max(xs)+1)/2; cy=(min(ys)+max(ys)+1)/2
    r=max(max(xs)-min(xs)+1, max(ys)-min(ys)+1)/2
    for (x,y) in pixels:
        if not s.has(x,y): continue
        t=((x+0.5-cx)+(y+0.5-cy))/(r*2**0.5)
        c='H'
        if t<hi_t: c='h'
        elif t>sh_t: c='g'
        if not s.boundary(x,y): s.paint[(x,y)]=c
        if internal:
            for dx,dy,kind in ((1,0,'1'),(0,1,'1'),(-1,0,'g'),(0,-1,'g')):
                q=(x+dx,y+dy)
                if s.has(*q) and q not in pixels:
                    # 只画在 pixels 这一侧
                    s.paint[(x,y)]=kind
    return s
