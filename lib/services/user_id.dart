import 'package:supasoka/services/user_identity.dart';

Future<String?> getOrCreateUserId() async {
  final id = await UserIdentity.getOrCreatePublicId();
  return id.trim().isEmpty ? null : id;
}
