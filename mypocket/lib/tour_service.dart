import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TourService {
  static String get _tourCompletedKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    return 'tour_completed_$userId';
  }

  /// Checks if the user has completed or skipped the tour before.
  static Future<bool> isTourCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_tourCompletedKey) ?? false;
    } catch (e) {
      // In case of error, default to true so we don't annoy the user with a broken overlay
      return true;
    }
  }

  /// Saves the tour completion status to SharedPreferences.
  static Future<void> markTourCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tourCompletedKey, true);
    } catch (e) {
      // ignore
    }
  }
}
