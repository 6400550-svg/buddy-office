# 人物美术规范（Buddy 办公室）

这个 App 的画面是一间像素风办公室：每个 Claude Code 会话是一个坐在工位上的像素小人（buddy）。
**平时看到的是背影**（从背后斜上方看过去）；需要用户时他会转过身来面向观众、举手。所以**背影的辨识度最重要**，其次是正面（脸、表情）。

参照物已经画好，请先看：`Character/Heads.swift`（头）、`Character/Hair.swift`（波波头 5 个朝向）、`Character/Torso.swift`（T 恤 5 个朝向、卫衣背/正面）。
用 `artctl strip --hair bob --outfit tee` 看五个朝向拼在一起的样子，**新画的东西要和它们一样细致、一样的光照和描边**。

## 画风
- 头身比很夸张的 Q 版（头 13 px，身体 10 px 躯干），柔和的像素风。光从**左上**来。
- 选择性描边：轮廓右下边缘用最深的描边色，左上边缘用比它浅一级的阴影色；内部贴左上边缘一圈高光、贴右下边缘一圈阴影；**不用纯黑**，**不做枕头式阴影**（阴影不是从四周往中间收）。这些 `ShadeKit.shade` 会自动做，你只需要画好**轮廓蒙版**，再用 `hi:`/`sh:` 坐标或 `overlay` 的 ASCII 补细节（发丝、褶皱、纽扣……）。
- 用户讨厌粗糙：轮廓要细致，要有细节（发型的层次、发丝、衣褶、高光、配饰）；同一个发型/衣服在 3 倍放大下（一个美术像素 = 6 个屏幕像素）要一眼认得出。
- **背影要互相区分得开**：发型和衣服的**轮廓形状**本身要有明显差别（不是只靠颜色）。

## 坐标与朝向
- 朝向有 5 个：`back`（背面）、`q34back`（3/4 背面）、`side`（侧面）、`q34front`（3/4 正面）、`front`（正面）。**全部画成「朝向画面右侧」的版本**，朝左的直接水平翻转，不用画。`Facing.name` 就是名字里的后缀。
- 头盒子 **12×13**（含头发共 13 高）：脸/头皮是第 3–12 行、第 1–10 列的圆脸（见 `CharacterArt.skullRows`），耳朵在第 0 / 11 列，下巴在第 12 行。头发从第 0 行开始盖上去。
- **头发 / 帽子 / 耳机 / 眼镜 / 发夹** 用同一张 **16×20** 的画布，头盒子左上角在 `CharacterArt.hairPad = (2, 3)`：所以头发可以往上伸 3 行、往下伸 4 行、往两边各伸 2 列。写蒙版时用**头盒子坐标**（`hairMask(rows, yStart:, xStart:)` 会帮你平移）。
- **躯干** 14 宽（第 0 行 = 肩线上沿），锚点 `neck`（脖子中心，头盒子的下巴中心 (6,12) 要对到躯干 `neck` 的上一行）、`shoulderL` / `shoulderR`（手臂接上去的位置，画面左/右）。背面/正面躯干 12 宽 + 两侧肩袖；侧面 8 宽。
- 合成顺序（后 → 前）：椅子后部 → 躯干 → 手臂 → 头 → 脸表情 → 头发 → 配饰（耳机/帽子/眼镜/发夹）→ 围巾（叠在躯干上，在头之后）→ 椅子前部。

## 角色字符（精灵格子里一个字符 = 一个「角色」，运行时再按每个人的外观换成具体颜色）
```
.  透明          _  （仅 overlay 用）擦成透明
k K j  肤色 高光/基/影          h H g  发色 高光/基/影          s S t  衣服 高光/基/影
p P    裤子 基/影               1 2 3  描边：发 / 肤 / 衣          e w m  眼 / 眼白 / 嘴
a A    点缀色 基/影（耳机、发夹、围巾、马克杯）   u  第二点缀（点缀色的高光级）
c C    椅子 基/影               r  夜间屏幕反光候选（画在头发/肩膀的高光位置，白天等于发/衣高光色）
b  腮红   o  鞋   n  高光白点   l  镜片
```
每个人的发色/肤色/衣服色/点缀色都不同，所以**只能用这些角色字符，不能写死颜色**。

## 工具（都在 `Character/ShadeKit.swift`）
- `Bitmap("""…""")`：任何非 `.`/空格的字符 = 有；`.offset/union/subtracting/fillRect/fillEllipse`；
- `ShadeKit.shade(bitmap, .hair | .cloth | .skin | .pants | .chair)` → `Grid`（自动描边 + 高光 + 阴影）；
- `Grid.overlay("""…""", dx:, dy:)`：用 ASCII 盖细节（`.` 不动，`_` 擦除）；`Grid[x, y] = Role.xxx` 直接改点；
- `CharacterArt.addHair(book, "名字", facing, mask:, hi: [(x,y)], sh: [(x,y)])`：头发的注册助手（坐标是头盒子坐标）；
- `book.add(grid.sprite(name:, anchors:))` 注册精灵；宽度不一致、字符不认识、锚点出界都会在 `artctl sheet` 里报错（必须为 0 个错误）。

## 怎么检查（必须看图，别凭想象）
1. 编译：`BUDDY_PKG=<你的包目录> BUDDY_SCRATCH=<你的scratch> scripts/dev.sh build`（**这条要用 dangerouslyDisableSandbox: true 运行**——SwiftPM 在沙箱里写不了用户临时目录，是实测出来的，不是让用户来验证；其他命令留在沙箱里）。
2. 出图（沙箱里可以直接跑）：
   - `artctl strip --seed N --hair <发型> --outfit <衣服> --zoom 10 --out x.png`：五个朝向拼一排；
   - `artctl sheet --filter <子串> --scale 10 --out x.png`：把匹配的精灵各放大一张；
   - `artctl cell --seed N --hair <发型> --outfit <衣服> --zoom 8 --out x.png`：整个工位（背影坐姿）——**背影在工位里看起来对不对，这张最重要**。
   用 Read 工具打开 PNG **亲眼看**。换几个 seed（发色、肤色、衣服色不同）都看一遍：浅色头发要能从浅色墙上分出来，深色头发的细节不能糊成一团。
3. 反复改到和参照物一样细致为止。

## 命名
`hair.<发型>.<朝向>`、`torso.<衣服>.<朝向>`、`acc.<配饰>.<朝向>`、`face.<表情>.<朝向>`、`arm.<姿势>[.<朝向>]`、`leg.<姿势>[.<朝向>]`、`chair.<款式>.<朝向>[.rear|.front]`。
发型名：`ponytail bun twinBuns long bob messy buzz curly`；衣服名：`tee hoodie cardigan shirt vest jacket`；配饰名：`headphones glasses beanie hairpin scarf`。
