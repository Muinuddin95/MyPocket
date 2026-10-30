// lib/subscription_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  static SubscriptionService get instance => _instance;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  final _supabase = Supabase.instance.client;

  Future<bool> checkPremiumStatus() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _isPremium = false;
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool('is_premium_$userId') ?? false;

      final res = await _supabase
          .from('users')
          .select('is_premium, premium_expires_at')
          .eq('user_id', userId)
          .maybeSingle();

      if (res != null) {
        bool premium = res['is_premium'] == true;

        if (premium && res['premium_expires_at'] != null) {
          final expiry = DateTime.tryParse(res['premium_expires_at'].toString());
          if (expiry != null && expiry.isBefore(DateTime.now())) {
            premium = false;
            await _expirePremium(userId);
          }
        }

        _isPremium = premium;
        await prefs.setBool('is_premium_$userId', premium);
      }

      return _isPremium;
    } catch (e) {
      debugPrint('SubscriptionService.checkPremiumStatus error: $e');
      return _isPremium;
    }
  }

  Future<bool> activatePremium() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final expiresAt = DateTime.now().add(const Duration(days: 30));

      await _supabase
          .from('users')
          .update({
            'is_premium': true,
            'premium_expires_at': expiresAt.toIso8601String(),
          })
          .eq('user_id', userId);

      _isPremium = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_premium_$userId', true);
      debugPrint('SubscriptionService: Premium activated until $expiresAt');
      return true;
    } catch (e) {
      debugPrint('SubscriptionService.activatePremium error: $e');
      return false;
    }
  }

  Future<void> _expirePremium(String userId) async {
    _isPremium = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_premium_$userId', false);
      await _supabase
          .from('users')
          .update({'is_premium': false})
          .eq('user_id', userId);
    } catch (_) {}
  }

  static const String defaultClientId = '';
  static const String defaultSecretKey = '';

  Future<Map<String, dynamic>> getPayPalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      final res = await _supabase
          .from('paypal_settings')
          .select('*')
          .eq('id', 'default')
          .maybeSingle();

      if (res != null) {
        final sandboxMode = res['sandbox_mode'] == true;
        final clientId = res['client_id']?.toString() ?? '';
        final secretKey = res['secret_key']?.toString() ?? '';
        final currency = res['currency']?.toString() ?? 'USD';
        final amount = (res['amount'] as num?)?.toDouble() ?? 2.20;

        await prefs.setBool('paypal_sandbox_mode', sandboxMode);
        await prefs.setString('paypal_client_id', clientId);
        await prefs.setString('paypal_secret_key', secretKey);
        await prefs.setString('paypal_currency', currency);
        await prefs.setDouble('paypal_amount', amount);

        return {
          'sandboxMode': sandboxMode,
          'clientId': clientId,
          'secretKey': secretKey,
          'currency': currency,
          'amount': amount,
          'synced': true,
        };
      }
    } catch (e) {
      debugPrint('SubscriptionService.getPayPalSettings Supabase error: $e');
    }

    // Offline / Local storage fallback
    final sandboxMode = prefs.getBool('paypal_sandbox_mode') ?? true;
    final clientId = prefs.getString('paypal_client_id') ?? defaultClientId;
    final secretKey = prefs.getString('paypal_secret_key') ?? defaultSecretKey;
    final currency = prefs.getString('paypal_currency') ?? 'USD';
    final amount = prefs.getDouble('paypal_amount') ?? 2.20;

    return {
      'sandboxMode': sandboxMode,
      'clientId': clientId,
      'secretKey': secretKey,
      'currency': currency,
      'amount': amount,
      'synced': false,
    };
  }

  Future<bool> savePayPalSettings({
    required bool sandboxMode,
    required String clientId,
    required String secretKey,
    required String currency,
    required double amount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('paypal_sandbox_mode', sandboxMode);
    await prefs.setString('paypal_client_id', clientId);
    await prefs.setString('paypal_secret_key', secretKey);
    await prefs.setString('paypal_currency', currency);
    await prefs.setDouble('paypal_amount', amount);

    try {
      await _supabase.from('paypal_settings').upsert({
        'id': 'default',
        'sandbox_mode': sandboxMode,
        'client_id': clientId,
        'secret_key': secretKey,
        'currency': currency,
        'amount': amount,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('SubscriptionService.savePayPalSettings Supabase error: $e');
      return false; // Dynamic table doesn't exist or permission denied, settings saved locally only
    }
  }
}

