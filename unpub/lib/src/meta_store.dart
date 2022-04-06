import 'package:unpub/src/models.dart';

abstract class MetaStore {
  Future<UnpubPackage?> queryPackage(String name);

  Future<void> addVersion(String name, UnpubVersion version);

  Future<void> addUploader(String name, String email);

  Future<void> removeUploader(String name, String email);

  void increaseDownloads(String name, String version);

  Future<UnpubQueryResult> queryPackages({
    required int size,
    required int page,
    required String sort,
    String? keyword,
    String? uploader,
    String? dependency,
  });

  Future<void> addUserToken(String email, String token);

  Future<bool> checkValidUser(String email, String password);

  Future<bool> checkAdminUser(String email, String password);

  Future<bool> isTokenValid(String token);

  Future<void> createUser(Map<String, dynamic> user);

  Future<void> changePassword(String email, String newPassword);
}
