    // ============ 寸头 buzz ============
    static func buildBuzz(_ book: SpriteBook) {
    // 背面：贴着头皮的极短发（H 为主，零星 g 做发茬、少量 h），只盖到第 9 行，发际线用 H/g 交错 + 几颗散落的发茬；耳朵和后颈露出来
    addHairFull(book, "buzz", .back, mask: """
        2@3| ######
        3@2| ########
        4@1| ##########
        5@1| ##########
        6@1| ##########
        7@1| ##########
        8@2| ########
        9@3| ######
        10@4| #
        10@8| #
        8@10| #
        """, detail: """
        2@4| rr
        3@3| rrHHHg
        4@2| hhHHHHHH
        5@2| hHHHHHHg
        6@2| HHHgHHHH
        7@1| gHHHHHHHgH
        8@2| ggHHHHHHg
        9@3| gHgHgH
        10@4| g
        10@8| g
        """)
    // 3/4 背面：同背面；右侧第 10–11 列第 8–10 行留给耳朵和脸颊
    addHairFull(book, "buzz", .threeQuarterBack, mask: """
        2@3| ######
        3@2| ########
        4@1| ##########
        5@1| ##########
        6@1| ##########
        7@1| ##########
        8@2| #######
        9@3| #####
        10@7| #
        """, detail: """
        2@4| rr
        3@3| rrHgHH
        4@2| hhHHHHgH
        5@2| hHHHHHHH
        6@2| HHHgHHHg
        7@1| gHgHHHHHgH
        8@2| gHHHHHg
        9@3| gHgHg
        10@7| g
        """)
    // 侧面：发盖住头顶和后脑上半，耳朵 (3–4, 8–10) 露出来
    addHairFull(book, "buzz", .side, mask: """
        2@3| ######
        3@2| ########
        4@1| #########
        5@1| ########
        6@1| ######
        7@1| #####
        8@1| ##
        9@1| ##
        """, detail: """
        3@3| hhHHHH
        4@2| hhHHHgHH
        5@2| HHHgHgH
        6@2| HHHHg
        7@2| HgHg
        8@2| g
        9@1| gH
        """)
    // 3/4 正面：发际线在额头上，鬓角一小截
    addHairFull(book, "buzz", .threeQuarterFront, mask: """
        2@3| ######
        3@2| ########
        4@1| ##########
        5@1| ####.##.##
        6@1| ##.......#
        7@1| ##
        5@5| #
        5@8| #
        """, detail: """
        3@3| hhHHgH
        4@2| hhHHHHgH
        5@2| HgHgHggg
        6@2| g
        6@10| g
        7@1| gH
        """)
    // 正面：平整的发际线，鬓角短，耳朵露出来
    addHairFull(book, "buzz", .front, mask: """
        2@3| ######
        3@2| ########
        4@1| ##########
        5@1| ###.##.###
        6@1| #........#
        7@1| #........#
        """, detail: """
        3@3| hhHgHH
        4@2| hhgHHHgH
        5@2| Hg
        5@5| gH
        5@8| Hg
        6@1| H
        6@10| g
        7@1| g
        7@10| H
        """)
    }
