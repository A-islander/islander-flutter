class ForumBoard {
  const ForumBoard({
    required this.id,
    required this.name,
    required this.description,
  });

  final int id;
  final String name;
  final String description;
}

class ForumReply {
  ForumReply({
    required this.id,
    required this.author,
    required this.time,
    required this.body,
  });

  final int id;
  final String author;
  final String time;
  final String body;
}

class ForumThread {
  ForumThread({
    required this.id,
    required this.boardId,
    required this.author,
    required this.time,
    required this.title,
    required this.body,
    required this.replies,
    required this.lastReply,
    required this.sage,
    required this.samples,
  });

  final int id;
  final int boardId;
  final String author;
  final String time;
  final String title;
  final String body;
  int replies;
  String lastReply;
  final int sage;
  final List<ForumReply> samples;
}

const forumBoards = <ForumBoard>[
  ForumBoard(id: 1, name: '议事厅', description: '站务、公共建设与岛内规则'),
  ForumBoard(id: 2, name: '综合', description: '没有固定方向的日常话题'),
  ForumBoard(id: 3, name: '技术', description: '开发、部署、协议与设备'),
];

List<ForumThread> buildForumThreads() => <ForumThread>[
  ForumThread(
    id: 1842,
    boardId: 1,
    author: '海盐-17',
    time: '2 分钟前',
    title: '下一处岛上地点，先做温室还是码头？',
    body: '海浪之家已经亮灯了。想听听大家觉得下一处更适合先做什么：能种下岛上原料的温室，还是能接住岛外来信的码头？',
    replies: 36,
    lastReply: 'No.1861',
    sage: 2,
    samples: <ForumReply>[
      ForumReply(
        id: 1843,
        author: '薄荷-03',
        time: '20:41',
        body: '我想先做温室，能和酒吧的搜集、行囊连起来。',
      ),
      ForumReply(
        id: 1844,
        author: '潮声-28',
        time: '20:47',
        body: 'No.1843 码头也可以先只做一个入口，不一定一开始就很复杂。',
      ),
      ForumReply(
        id: 1845,
        author: '海盐-42',
        time: '21:02',
        body: '可以先把全岛天气接进来，两边都会需要。 (´▽｀)',
      ),
    ],
  ),
  ForumThread(
    id: 1838,
    boardId: 3,
    author: '纸船-09',
    time: '18 分钟前',
    title: '关于 Web 和 Flutter 共用设计 token 的草案',
    body:
        '建议只共享语义，不共享组件源码。Web 输出 CSS variables，Flutter 输出 ThemeExtension，各走各的平台实现。',
    replies: 18,
    lastReply: 'No.1860',
    sage: 0,
    samples: <ForumReply>[
      ForumReply(
        id: 1839,
        author: '岛灯-12',
        time: '19:25',
        body: '颜色之外，文案 key 和错误类型也值得一起管。',
      ),
      ForumReply(
        id: 1841,
        author: '海盐-42',
        time: '20:06',
        body: '先拿串、编辑器、饼干三个模块验证应该够。',
      ),
    ],
  ),
  ForumThread(
    id: 1829,
    boardId: 2,
    author: '晚潮-21',
    time: '1 小时前',
    title: '雨夜的海浪之家',
    body: '刚刚点到一杯海角黄昏。窗外下着雨，岛民娘说柠檬像一小块被云漏下来的光。',
    replies: 24,
    lastReply: 'No.1856',
    sage: 1,
    samples: <ForumReply>[
      ForumReply(
        id: 1830,
        author: '玻璃杯-06',
        time: '00:03',
        body: '安静的环境音挺好，正文区域保持清楚就行。',
      ),
    ],
  ),
  ForumThread(
    id: 1817,
    boardId: 2,
    author: '北岸-11',
    time: '3 小时前',
    title: '分享一下今天看到的云',
    body: '像一艘没有桅杆的船，慢慢从岛的北边过去了。',
    replies: 9,
    lastReply: 'No.1851',
    sage: 0,
    samples: <ForumReply>[
      ForumReply(
        id: 1818,
        author: '白沙-04',
        time: '18:44',
        body: '从我这里看更像一头鲸鱼。',
      ),
    ],
  ),
  ForumThread(
    id: 1804,
    boardId: 3,
    author: '折线-08',
    time: '昨天',
    title: '旧接口的分页参数需要统一一下',
    body: '时间线和板块页对 page、pageSize 的默认值不一致，迁移前最好先在请求层做一次归一化。',
    replies: 12,
    lastReply: 'No.1849',
    sage: 0,
    samples: <ForumReply>[
      ForumReply(id: 1808, author: '纸船-09', time: '昨天', body: '可以先补契约测试，再换页面。'),
    ],
  ),
];
