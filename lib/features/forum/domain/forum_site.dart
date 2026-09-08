import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Endpoint-bound identity: alternate deployments never share private state.
class ForumSite {
  ForumSite({
    required this.id,
    required this.name,
    required String endpoint,
    required this.webUrl,
    String? identityEndpoint,
  }) : endpoint = _normalize(endpoint),
       identityEndpoint = identityEndpoint == null
           ? null
           : _normalize(identityEndpoint);

  final String id;
  final String name;
  final String endpoint;
  final String? identityEndpoint;
  final String webUrl;
  String get instanceKey =>
      '$id:${sha256.convert(utf8.encode('$endpoint|${identityEndpoint ?? ''}'))}';
  bool get isIslander => id == 'islander';

  static String _normalize(String value) {
    final uri = Uri.parse(value);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('站点地址必须为不含凭证、查询参数的 HTTP(S) 地址');
    }
    return uri
        .replace(path: '${uri.path.replaceAll(RegExp(r'/+$'), '')}/')
        .toString();
  }

  static final islander = ForumSite(
    id: 'islander',
    name: '岛民岛',
    endpoint: const String.fromEnvironment(
      'FORUM_API_URL',
      defaultValue: 'https://forum-api.islander.top/',
    ),
    identityEndpoint: const String.fromEnvironment(
      'USER_API_URL',
      defaultValue: 'https://user-api.islander.top/',
    ),
    webUrl: 'https://islander.top/',
  );
  static final x = ForumSite(
    id: 'x',
    name: 'X 岛',
    endpoint: 'https://api.nmb.best/api/',
    webUrl: 'https://www.nmbxd.com/',
  );
  static final bog = ForumSite(
    id: 'bog',
    name: 'BOG',
    endpoint: 'https://bog.ac/',
    webUrl: 'https://bog.ac/',
  );
  static List<ForumSite> get all => [islander, x, bog];
  static ForumSite byId(String id) => all.firstWhere(
    (s) => s.id == id,
    orElse: () => throw ArgumentError('未知站点'),
  );

  String route(String path) => isIslander ? path : '/s/$id$path';
}

class PostKey {
  const PostKey(this.siteInstanceKey, this.id);
  final String siteInstanceKey;
  final String id;
  @override
  bool operator ==(Object other) =>
      other is PostKey &&
      other.siteInstanceKey == siteInstanceKey &&
      other.id == id;
  @override
  int get hashCode => Object.hash(siteInstanceKey, id);
  @override
  String toString() => '$siteInstanceKey/$id';
}

class ForumCapabilities {
  const ForumCapabilities({
    this.publish = false,
    this.reply = false,
    this.mine = false,
    this.sage = false,
    this.manage = false,
    this.verify = false,
    this.register = false,
    this.locate = false,
  });
  final bool publish, reply, mine, sage, manage, verify, register, locate;
  bool canPublish(bool isReply) => isReply ? reply : publish;
  static const islander = ForumCapabilities(
    publish: true,
    reply: true,
    mine: true,
    sage: true,
    manage: true,
    verify: true,
    register: true,
    locate: true,
  );
}
