import 'package:app_links/app_links.dart';

abstract class IncomingLinkService {
  Future<Uri?> getInitialUri();

  Stream<Uri> get uriLinks;
}

class PlatformIncomingLinkService implements IncomingLinkService {
  PlatformIncomingLinkService({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialUri() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get uriLinks => _appLinks.uriLinkStream;
}
