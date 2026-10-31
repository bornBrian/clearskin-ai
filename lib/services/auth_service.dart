import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../data/repositories/repositories.dart';

/// A signed-in account. Personal skin data still lives only on the phone;
/// the account keeps Premium attached to the person across reinstalls and
/// devices.
class Account {
  const Account({required this.provider, this.email, this.name});

  /// "google", "apple" or "email".
  final String provider;
  final String? email;
  final String? name;

  /// Stable identity used to tell whose data is on the phone.
  String get key => (email ?? provider).trim().toLowerCase();

  Map<String, Object?> toJson() => {
    'provider': provider,
    'email': email,
    'name': name,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    provider: j['provider'] as String? ?? 'email',
    email: j['email'] as String?,
    name: j['name'] as String?,
  );
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.cancelled = false});
  final String message;

  /// The person closed the sheet — show nothing.
  final bool cancelled;

  @override
  String toString() => 'AuthFailure($message)';
}

/// Google, Apple (iPhone) and passwordless e-mail sign-in on top of the
/// app's Supabase session.
///
/// Google and Apple *link* the identity to the existing anonymous session,
/// so the user id — and therefore any RevenueCat purchase — stays the same.
/// E-mail codes sign in to the e-mail's account (or create it).
///
/// Without a backend (debug demo mode) both flows succeed locally so every
/// screen can be exercised.
class AuthService {
  AuthService(this._kv);
  final KeyValueStore _kv;

  bool _googleReady = false;

  /// Google can only be set up once per app run, so one secure random
  /// nonce serves the run: Google signs its hash into the ID token and
  /// Supabase only accepts that token with this raw value, which never
  /// leaves the app. A token stolen in transit or from a log can't be
  /// replayed elsewhere.
  final String _googleNonce = _nonce();

  /// Google sign-in needs its own iOS client; without one the button is
  /// hidden on iPhone rather than failing.
  static bool get googleAvailable =>
      !Platform.isIOS || Env.googleIosClientId.isNotEmpty;

  /// Sign in with Apple: offered on iPhone, as Apple requires next to
  /// Google sign-in.
  static bool get appleAvailable => Platform.isIOS;

  Future<Account?> current() async {
    final j = await _kv.getJson(KvKeys.account);
    return j == null ? null : Account.fromJson(j);
  }

  Future<Account> signInWithGoogle() async {
    if (Env.googleWebClientId.isEmpty) {
      // No Google credentials at all: only a debug demo can stand in.
      if (!Env.hasBackend) return _demo('google', 'you@gmail.com');
      throw const AuthFailure('Google sign-in isn\'t set up in this build.');
    }
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(
          serverClientId: Env.googleWebClientId,
          nonce: sha256.convert(utf8.encode(_googleNonce)).toString(),
          clientId: Platform.isIOS && Env.googleIosClientId.isNotEmpty
              ? Env.googleIosClientId
              : null,
        );
        _googleReady = true;
      }
      final user = await GoogleSignIn.instance.authenticate();
      final idToken = user.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure('Google didn\'t return a sign-in token.');
      }
      final account = Account(
        provider: 'google',
        email: user.email,
        name: user.displayName,
      );
      // A real Google identity, verified by Google. Without the backend
      // (local testing) there's no server account to attach it to yet.
      if (!Env.hasBackend) return await _save(account);
      await _attach(OAuthProvider.google, idToken, nonce: _googleNonce);
      return await _save(account);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // Android reports an app whose signing key isn't registered with
        // Google as a "cancel" after the account is chosen ([16] Account
        // reauth failed / [10] developer error). Say so, rather than
        // silently dropping the person back on the sign-in screen.
        final why = e.description ?? '';
        if (why.contains('[16]') ||
            why.contains('[10]') ||
            why.toLowerCase().contains('reauth')) {
          throw const AuthFailure(
            'Google sign-in isn\'t set up for this app version yet. Try email instead.',
          );
        }
        throw const AuthFailure('', cancelled: true);
      }
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      throw AuthFailure(switch (e.code) {
        // Almost always an OAuth client / SHA-1 mismatch in Google Cloud.
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in isn\'t set up for this app version yet.',
        _ => 'Google sign-in didn\'t work. Try again.',
      });
    } on AuthException catch (e) {
      debugPrint('Supabase Google sign-in failed: ${e.message}');
      throw const AuthFailure('Couldn\'t sign you in. Try again.');
    } on SocketException {
      throw const AuthFailure('You\'re offline.');
    }
  }

  Future<Account> signInWithApple() async {
    if (!Env.hasBackend) return _demo('apple', 'you@icloud.com');
    // Apple signs a hash of the nonce into the token; Supabase checks the
    // raw value against it, so a stolen token can't be replayed.
    final rawNonce = _nonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthFailure('Apple didn\'t return a sign-in token.');
      }
      await _attach(OAuthProvider.apple, idToken, nonce: rawNonce);
      unawaited(_keepAppleToken(credential.authorizationCode));
      // Apple shares the name (and e-mail) only the first time; after that
      // keep what the account already has.
      final previous = await current();
      final name = [
        credential.givenName,
        credential.familyName,
      ].whereType<String>().join(' ').trim();
      return await _save(
        Account(
          provider: 'apple',
          email:
              credential.email ??
              Supabase.instance.client.auth.currentUser?.email ??
              previous?.email,
          name: name.isNotEmpty ? name : previous?.name,
        ),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthFailure('', cancelled: true);
      }
      debugPrint('Apple sign-in failed: ${e.code} ${e.message}');
      throw const AuthFailure('Apple sign-in didn\'t work. Try again.');
    } on SignInWithAppleException catch (e) {
      debugPrint('Apple sign-in unavailable: $e');
      throw const AuthFailure('Apple sign-in isn\'t available right now.');
    } on AuthException catch (e) {
      debugPrint('Supabase Apple sign-in failed: ${e.message}');
      throw const AuthFailure('Couldn\'t sign you in. Try again.');
    } on SocketException {
      throw const AuthFailure('You\'re offline.');
    }
  }

  /// Lets the server revoke ClearSkin's Apple access if the account is
  /// deleted (Apple requires it). Sign-in never waits on this.
  Future<void> _keepAppleToken(String code) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'apple-token',
        body: {'authorization_code': code},
      );
    } catch (e) {
      debugPrint('Apple token not kept: $e');
    }
  }

  /// Links [idToken]'s identity to the anonymous session, or signs in to
  /// the account that identity already belongs to.
  Future<void> _attach(
    OAuthProvider provider,
    String idToken, {
    String? nonce,
  }) async {
    final auth = Supabase.instance.client.auth;
    final anon = auth.currentUser?.isAnonymous ?? false;
    if (anon) {
      try {
        await auth.linkIdentityWithIdToken(
          provider: provider,
          idToken: idToken,
          nonce: nonce,
        );
        return;
      } on AuthException {
        // This identity already belongs to a ClearSkin user (e.g. a
        // reinstall): sign in to that account instead.
      }
    }
    await auth.signInWithIdToken(
      provider: provider,
      idToken: idToken,
      nonce: nonce,
    );
  }

  static String _nonce() {
    final random = Random.secure();
    return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
  }

  /// Sends a 6-digit code to [email].
  Future<void> sendEmailCode(String email) async {
    if (!Env.hasBackend) return;
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: true,
      );
    } on AuthException catch (e) {
      debugPrint('OTP send failed: ${e.message}');
      throw const AuthFailure('Couldn\'t send the code. Check the address.');
    } on SocketException {
      throw const AuthFailure('You\'re offline.');
    }
  }

  Future<Account> verifyEmailCode(String email, String code) async {
    if (!Env.hasBackend) return _demo('email', email.trim());
    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.email,
      );
      return await _save(Account(provider: 'email', email: email.trim()));
    } on AuthException {
      throw const AuthFailure('That code didn\'t match. Try again.');
    } on SocketException {
      throw const AuthFailure('You\'re offline.');
    }
  }

  Future<void> signOut() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
      if (Env.hasBackend) await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Sign-out: $e');
    }
    await _kv.remove(KvKeys.account);
  }

  Future<Account> _demo(String provider, String email) async {
    if (!kDebugMode) {
      throw const AuthFailure('Sign-in isn\'t available in this build.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return _save(Account(provider: provider, email: email));
  }

  Future<Account> _save(Account a) async {
    await _kv.setJson(KvKeys.account, a.toJson());
    return a;
  }
}
