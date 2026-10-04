import 'package:app_links/app_links.dart';

abstract class IncomingLinkService {
  Stream<Uri> get uriLinks;
}

class PlatformIncomingLinkService implements IncomingLinkService {
  PlatformIncomingLinkService({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Stream<Uri> get uriLinks => _appLinks.uriLinkStream;
}
