# heap 类别差（实验 1：t=150 s → t=960 s；只列增长最多的 12 类，字节 / 个数）

## B 有提醒（8 个会话压力 replay，静音）

- +123344 字节 / +105 个：CFData
- +102880 字节 / +0 个：Swift._ContiguousArrayStorage<BuddyCore.HookEvent>
- +71680 字节 / +0 个：Swift._DictionaryStorage<Swift.UInt64, BuddyCore.TokenLedger.Rec>
- +33648 字节 / +862 个：CFString
- +33600 字节 / +105 个：CGImage
- +33600 字节 / +105 个：CGDataProvider
- +29184 字节 / +0 个：Swift._ContiguousArrayStorage<BuddyCore.ClosedTool>
- +21280 字节 / +95 个：CFAllocator
- +20160 字节 / +105 个：CA::Render::Image
- +18432 字节 / +0 个：Swift._DictionaryStorage<PixelKit.TextRenderer.(Key in $10435bac0), PixelKit.Tex
- +18432 字节 / +0 个：Swift._ContiguousArrayStorage<BuddyCore.TranscriptFacts.OpenToolUse>
- +16384 字节 / +1 个：Swift Metadata

## C 没有提醒（同样的数据量，--wait-prob 0）

- +138960 字节 / +90 个：CFData
- +80800 字节 / +0 个：Swift._ContiguousArrayStorage<BuddyCore.HookEvent>
- +71680 字节 / +0 个：Swift._DictionaryStorage<Swift.UInt64, BuddyCore.TokenLedger.Rec>
- +28800 字节 / +90 个：CGImage
- +28800 字节 / +90 个：CGDataProvider
- +25168 字节 / +651 个：CFString
- +21504 字节 / +0 个：Swift._ContiguousArrayStorage<BuddyCore.ClosedTool>
- +18656 字节 / +245 个：non-object
- +18432 字节 / +0 个：Swift._DictionaryStorage<PixelKit.TextRenderer.(Key in $1007dbac0), PixelKit.Tex
- +17696 字节 / +79 个：CFAllocator
- +17280 字节 / +90 个：CA::Render::Image
- +16384 字节 / +1 个：Swift Metadata
