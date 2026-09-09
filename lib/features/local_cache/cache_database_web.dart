import 'dart:async';
import 'dart:js_interop';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:web/web.dart' as web;

Future<void>? _lease;

// A dedicated worker avoids intermittent SharedWorker request stalls. Its
// IndexedDB-backed file system is not coherent across tabs, so retain an
// exclusive origin lock until this document closes. Never steal another tab's
// lock or run two independent SQLite writers against the same database.
Future<void> _acquireLease() async {
  final acquired = Completer<void>();
  unawaited(
    web.window.navigator.locks
        .request(
          'islander-cache-v1',
          web.LockOptions(ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null) {
              acquired.completeError(StateError('本地缓存正在其他标签页中使用，请关闭其他标签页后重试'));
              return null;
            }
            acquired.complete();
            // Browsers release this lock automatically when the page closes.
            return Completer<JSAny?>().future.toJS;
          }).toJS,
        )
        .toDart
        .catchError((Object error) {
          if (!acquired.isCompleted) acquired.completeError(error);
          return null;
        }),
  );
  await acquired.future;
}

Future<Database> openCacheDatabase() async {
  try {
    await (_lease ??= _acquireLease());
  } catch (_) {
    _lease = null;
    rethrow;
  }
  return databaseFactoryFfiWebBasicWebWorker
      .openDatabase('islander-cache-v1.db')
      .timeout(const Duration(seconds: 20));
}
