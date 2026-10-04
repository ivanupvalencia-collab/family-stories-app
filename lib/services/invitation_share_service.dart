import 'package:share_plus/share_plus.dart';

abstract class InvitationShareService {
  Future<void> shareInvitation(String token);
}

class PlatformInvitationShareService implements InvitationShareService {
  @override
  Future<void> shareInvitation(String token) async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Te invito a conectar conmigo en Family Stories.\n'
            'Código de invitación: $token',
      ),
    );
  }
}
