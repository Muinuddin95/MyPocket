import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F4),
      appBar: AppBar(
        title: const Text('FAQ & Help Center', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E5641),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('Account'),
          _buildFaqItem(
            'How do I change my password?',
            'You can reset your password by logging out and tapping the "Forgot Password?" link on the login screen. An email will be sent to you with a reset link.',
          ),
          _buildFaqItem(
            'Can I edit my profile picture?',
            'Yes! You can edit your profile picture by tapping on your avatar in the Home Screen or Settings tab, which allows you to take a photo or choose from your gallery.',
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('Budgeting & Limits'),
          _buildFaqItem(
            'How do I set a daily allowance limit?',
            'Go to the Settings tab, tap on "Daily Allowance Limit", and enter your desired amount. We will send you a notification if you exceed this limit in a single day.',
          ),
          _buildFaqItem(
            'How do Savings Goals work?',
            'You can create multiple savings goals from the Home tab. As you add funds to your goals, MyPocket will track your progress with a percentage bar until you hit your target!',
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('Premium Features'),
          _buildFaqItem(
            'What is Premium Analytics?',
            'Premium Analytics gives you access to advanced charts, PDF exports of your transactions, and deeper insights into your spending habits over time.',
          ),
          _buildFaqItem(
            'How do I cancel my subscription?',
            'You can manage your PayPal subscription directly from the Settings tab by selecting "Subscription Details".',
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              'Still need help? Tap Customer Support in Settings.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF2E9B78),
          letterSpacing: 1.2,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: const Color(0xFF1E5641),
          collapsedIconColor: Colors.grey,
          title: Text(
            question,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Text(
                answer,
                style: const TextStyle(color: Colors.black87, height: 1.5, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
