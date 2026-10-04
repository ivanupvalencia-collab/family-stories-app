import 'package:share_plus/share_plus.dart';

import 'invitation_link.dart';

abstract class InvitationShareService {
  Future<void> shareInvitation(String token);
}

class PlatformInvitationShareService implements InvitationShareService {
  @override
  Future<void> shareInvitation(String token) async {
    final link = InvitationLink.build(token);
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Te invito a conectar conmigo en Family Stories.\n'
            'Pulsa aquí para aceptar la invitación:\n$link',
      ),
    );
  }
}
