import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openCacheDatabase() async {
  final directory = await getApplicationSupportDirectory();
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    '${directory.path}/islander-cache-v1.db',
  );
}
