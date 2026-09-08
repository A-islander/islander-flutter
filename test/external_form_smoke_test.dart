import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/data/adapters/external_writer.dart';

class _PublicHttp extends HttpOverrides {}

void main() {
  test(
    'public forms still match the posting parser; GET only, no identity',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final http = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 25),
            responseType: ResponseType.plain,
            followRedirects: false,
          ),
        );
        try {
          for (final example in [
            (
              site: 'x',
              url: 'https://www.nmbxd1.com/f/综合版1',
              boardId: 4,
              boardName: '综合版1',
              threadId: null,
            ),
            (
              site: 'x',
              url: 'https://www.nmbxd1.com/t/50000001',
              boardId: 4,
              boardName: null,
              threadId: 50000001,
            ),
            (
              site: 'bog',
              url: 'https://bog.ac/f/综合版/1',
              boardId: 0,
              boardName: '综合版',
              threadId: null,
            ),
            (
              site: 'bog',
              url: 'https://bog.ac/t/1526630/1',
              boardId: 0,
              boardName: null,
              threadId: 1526630,
            ),
          ]) {
            final page = Uri.parse(example.url);
            final result = await http.getUri<String>(page);
            final form = ExternalWriter.parseForm(
              result.data!,
              page: page,
              site: example.site,
              body: 'parser validation only',
              title: '表单检查（不会提交）',
              boardId: example.boardId,
              boardName: example.boardName,
              threadId: example.threadId,
            );
            expect(form.action.origin, page.origin);
            // Deliberately do not send form fields, attach cookies, or print tokens/content.
          }
        } finally {
          http.close(force: true);
        }
      }, _PublicHttp());
    },
    skip: !const bool.fromEnvironment('RUN_EXTERNAL_FORM_SMOKE'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
