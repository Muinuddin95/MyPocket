import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminChatListScreen extends StatefulWidget {
  const AdminChatListScreen({Key? key}) : super(key: key);

  @override
  State<AdminChatListScreen> createState() => _AdminChatListScreenState();
}

class _AdminChatListScreenState extends State<AdminChatListScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _chatUsers = [];

  @override
  void initState() {
    super.initState();
    _loadChatUsers();
  }

  Future<void> _loadChatUsers() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all messages to find unique users and their latest message
      final messagesRes = await _supabase
          .from('support_messages')
          .select('user_id, content, created_at, is_from_admin')
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> latestMessages = {};
      for (var m in messagesRes as List) {
        final uid = m['user_id'].toString();
        if (!latestMessages.containsKey(uid)) {
          latestMessages[uid] = m as Map<String, dynamic>;
        }
      }

      if (latestMessages.isEmpty) {
        if (mounted) {
          setState(() {
            _chatUsers = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch user details for those user_ids
      final userIds = latestMessages.keys.toList();
      final usersRes = await _supabase
          .from('users')
          .select('*')
          .filter('user_id', 'in', userIds);

      final List<Map<String, dynamic>> combined = [];
      for (var u in usersRes as List) {
        final uid = u['user_id'].toString();
        combined.add({
          'user': u,
          'latest_message': latestMessages[uid],
        });
      }

      // Sort by latest message date
      combined.sort((a, b) {
        final aDate = DateTime.parse(a['latest_message']['created_at']);
        final bDate = DateTime.parse(b['latest_message']['created_at']);
        return bDate.compareTo(aDate);
      });

      if (mounted) {
        setState(() {
          _chatUsers = combined;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load chats: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F4),
      appBar: AppBar(
        title: const Text('Active Support Chats', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E5641),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E5641)))
          : _chatUsers.isEmpty
              ? const Center(child: Text('No active support chats.', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadChatUsers,
                  child: ListView.builder(
                    itemCount: _chatUsers.length,
                    itemBuilder: (context, index) {
                      final item = _chatUsers[index];
                      final user = item['user'];
                      final latestMsg = item['latest_message'];
                      final bool isFromAdmin = latestMsg['is_from_admin'] == true;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF1E5641).withValues(alpha: 0.1),
                            backgroundImage: (user['avatar_base64'] != null && user['avatar_base64'].toString().isNotEmpty)
                                ? MemoryImage(
                                    base64Decode(
                                      user['avatar_base64'].toString().contains(',')
                                          ? user['avatar_base64'].toString().split(',')[1]
                                          : user['avatar_base64'].toString(),
                                    ),
                                  )
                                : null,
                            child: (user['avatar_base64'] == null || user['avatar_base64'].toString().isEmpty)
                                ? Text(
                                    user['name']?.substring(0, 1).toUpperCase() ?? 'U',
                                    style: const TextStyle(color: Color(0xFF1E5641), fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(user['name'] ?? 'Unknown User', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            isFromAdmin ? 'You: ${latestMsg['content']}' : latestMsg['content'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isFromAdmin ? Colors.grey : Colors.black87,
                              fontWeight: isFromAdmin ? FontWeight.normal : FontWeight.w500,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminChatDetailScreen(user: user),
                              ),
                            ).then((_) => _loadChatUsers());
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class AdminChatDetailScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const AdminChatDetailScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<AdminChatDetailScreen> createState() => _AdminChatDetailScreenState();
}

class _AdminChatDetailScreenState extends State<AdminChatDetailScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await _supabase.from('support_messages').insert({
        'user_id': widget.user['user_id'],
        'is_from_admin': true,
        'content': text,
      });
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F4),
      appBar: AppBar(
        title: Text(
          widget.user['name'] ?? 'User',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E5641),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/logo.png'),
            fit: BoxFit.contain,
            opacity: 0.05,
            alignment: Alignment.center,
          ),
        ),
        child: Column(
          children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('support_messages')
                  .stream(primaryKey: ['id'])
                  .eq('user_id', widget.user['user_id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return const Center(child: Text('No messages found.'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Display messages from bottom to top
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isFromAdmin = msg['is_from_admin'] == true;

                    return Align(
                      alignment: isFromAdmin ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isFromAdmin ? const Color(0xFF1E5641) : Colors.white,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isFromAdmin ? const Radius.circular(0) : const Radius.circular(16),
                            bottomLeft: isFromAdmin ? const Radius.circular(16) : const Radius.circular(0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          msg['content'] ?? '',
                          style: TextStyle(
                            color: isFromAdmin ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Reply to ${widget.user['name']}...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1E5641),
                    child: IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _isLoading ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
