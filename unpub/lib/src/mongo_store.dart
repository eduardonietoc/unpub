import 'package:mongo_dart/mongo_dart.dart';
import 'package:intl/intl.dart';
import 'package:unpub/src/models.dart';
import 'meta_store.dart';
import 'package:crypt/crypt.dart';

final String packageCollection = 'packages';
final String statsCollection = 'stats';
final String userCollection = 'users';
final String tokenCollection = 'tokens';

class MongoStore extends MetaStore {
  Db db;

  MongoStore(this.db);

  static SelectorBuilder _selectByName(String? name) => where.eq('name', name);

  Future<UnpubQueryResult> _queryPackagesBySelector(
      SelectorBuilder selector) async {
    final count = await db.collection(packageCollection).count(selector);
    final packages = await db
        .collection(packageCollection)
        .find(selector)
        .map((item) => UnpubPackage.fromJson(item))
        .toList();
    return UnpubQueryResult(count, packages);
  }

  @override
  queryPackage(name) async {
    var json =
        await db.collection(packageCollection).findOne(_selectByName(name));
    if (json == null) return null;
    return UnpubPackage.fromJson(json);
  }

  @override
  addVersion(name, version) async {
    await db.collection(packageCollection).update(
        _selectByName(name),
        modify
            .push('versions', version.toJson())
            .addToSet('uploaders', version.uploader)
            .setOnInsert('createdAt', version.createdAt)
            .setOnInsert('private', true)
            .setOnInsert('download', 0)
            .set('updatedAt', version.createdAt),
        upsert: true);
  }

  @override
  addUploader(name, email) async {
    await db
        .collection(packageCollection)
        .update(_selectByName(name), modify.push('uploaders', email));
  }

  @override
  removeUploader(name, email) async {
    await db
        .collection(packageCollection)
        .update(_selectByName(name), modify.pull('uploaders', email));
  }

  @override
  increaseDownloads(name, version) {
    var today = DateFormat('yyyyMMdd').format(DateTime.now());
    db
        .collection(packageCollection)
        .update(_selectByName(name), modify.inc('download', 1));
    db
        .collection(statsCollection)
        .update(_selectByName(name), modify.inc('d$today', 1));
  }

  @override
  Future<UnpubQueryResult> queryPackages({
    required size,
    required page,
    required sort,
    keyword,
    uploader,
    dependency,
  }) {
    var selector =
        where.sortBy(sort, descending: true).limit(size).skip(page * size);

    if (keyword != null) {
      selector = selector.match('name', '.*$keyword.*');
    }
    if (uploader != null) {
      selector = selector.eq('uploaders', uploader);
    }
    if (dependency != null) {
      selector = selector.raw({
        'versions': {
          r'$elemMatch': {
            'pubspec.dependencies.$dependency': {r'$exists': true}
          }
        }
      });
    }

    return _queryPackagesBySelector(selector);
  }

  @override
  Future<void> addUserToken(String email, String token) async => await db
      .collection(userCollection)
      .updateOne(where.eq('email', email), modify.set('token', token));

  bool passwordIsValid(String cryptFormatHash, String enteredPassword) =>
      Crypt(cryptFormatHash).match(enteredPassword);

  @override
  Future<bool> checkValidUser(String email, String password) async {
    Map<String, dynamic>? result =
        await db.collection(userCollection).findOne(where.eq('email', email));

    if (result == null) {
      return false;
    }

    String? userPass = result['password'];

    if (password != userPass) {
      return passwordIsValid(userPass!, password);
    }

    return password == userPass;
  }

  @override
  Future<bool> isTokenValid(String token) async {
    Map<String, dynamic>? result =
        await db.collection(userCollection).findOne(where.eq('token', token));

    return result != null;
  }

  @override
  Future<void> createUser(Map<String, dynamic> newUser) async {
    await db.collection(userCollection).insert(newUser);
  }

  @override
  Future<void> changePassword(String email, String newPassword) async {
    Crypt newPass = Crypt.sha512(newPassword);

    await db.collection(userCollection).update(
        where.eq('email', email), modify.set('password', newPass.toString()));
  }

  @override
  Future<bool> checkAdminUser(String email, String password) async {
    bool isValidUser = await checkValidUser(email, password);

    print('user is valid $isValidUser');

    if (isValidUser) {
      Map<String, dynamic>? result =
          await db.collection(userCollection).findOne(
                where.eq('email', email).and(where.eq('admin', true)),
              );
      return result != null;
    }
    return false;
  }

  @override
  Future<String> getUploaderEmail(String token) async {
    Map<String, dynamic>? result = await db.collection(userCollection).findOne(
          where.eq('token', token),
        );

    if (result != null) {
      return result['email'];
    }
    return '';
  }

  @override
  Future<void> checkConnection() async {
    if (!db.isConnected) {
      await db
        ..close()
        ..open();
    }
  }
}
