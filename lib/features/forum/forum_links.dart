import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'forum_theme.dart';

// Static navigation from islander-vue-web/src/App.vue, in the original order.
// These links are not part of the plate/get response.
const forumSiteLinks = <({String label, String url})>[
  (label: '岛民hub', url: 'http://gitea.islander.top'),
  (label: '串备份地址', url: 'https://github.com/A-islander/post-backup'),
  (
    label: '接口文档',
    url: 'https://docs.apipost.cn/preview/b58077f3ebc9caeb/6a197cc600cf6f5c',
  ),
];

const forumFriendLinks = <({String label, String url})>[
  (label: 'x岛（三酱岛）', url: 'https://www.nmbxd.com'),
  (label: '脑洞', url: 'https://www.naodong.fun'),
  (label: 'bog岛', url: 'http://bog.ac'),
  (label: '欢乐恶狗岛', url: 'https://huanleegao.com/t'),
  (label: '钉幕石之音', url: 'https://mszym.top/'),
];

class ForumExternalLinks extends StatelessWidget {
  const ForumExternalLinks({super.key});

  Future<void> _open(BuildContext context, String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (opened) return;
    } catch (_) {
      // The URL launcher may be unavailable on a device or blocked by a browser.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查浏览器设置后重试')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final group in [
        (title: '站务', links: forumSiteLinks),
        (title: '友链', links: forumFriendLinks),
      ]) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text(
            group.title,
            style: const TextStyle(fontSize: 10, color: ForumColors.muted),
          ),
        ),
        for (final link in group.links)
          Semantics(
            link: true,
            child: Tooltip(
              message: link.url,
              child: InkWell(
                onTap: () => _open(context, link.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          link.label,
                          style: const TextStyle(
                            fontSize: 13,
                            color: ForumColors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.north_east,
                        size: 13,
                        color: ForumColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ],
  );
}
