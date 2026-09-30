发型设计脚本（参考用，交付物是 Sources/BuddyArt/Character/HairStyles.swift，里面全是可以直接手改的 ASCII）。
- 环境变量 SP = 输出目录（里面要有 styles/），SRC = 最终 HairStyles.swift 的路径；
- 每个 *_design.py 生成 styles/<发型>.swift；ponytail 是手写的（styles/ponytail.swift 直接改）；
- assemble.py 把 styles/_header.swift + 七个发型拼成 HairStyles.swift；
- 免编译预览：artctl lab / labcell / dump / check 都带 --live <HairStyles.swift 路径>（见 Sources/BuddyArt/HairLab.swift，只在这份拷贝里）。
