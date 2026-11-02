import 'package:clearskin_ai/core/config/app_store.dart';
import 'package:clearskin_ai/features/share/invite_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing tags the source for Play Console', () {
    expect(
      AppStore.listing('share_card'),
      'https://play.google.com/store/apps/details?id=com.clearskinai.app'
      '&referrer=utm_source%3Dshare_card',
    );
  });

  test('invite links carry the code as the campaign', () {
    expect(
      InviteScreen.link('K7QAMX'),
      'https://play.google.com/store/apps/details?id=com.clearskinai.app'
      '&referrer=utm_source%3Dreferral%26utm_campaign%3DK7QAMX',
    );
  });
}
