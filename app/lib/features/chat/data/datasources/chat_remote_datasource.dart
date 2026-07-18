import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class ChatMessage {
  final String id;
  final String bookingId;
  final String senderId;
  final String content;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.content,
    required this.sentAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String,
      sentAt: DateTime.parse(map['sent_at'] as String).toLocal(),
    );
  }
}

class ChatRemoteDataSource {
  final SupabaseClient _client;

  ChatRemoteDataSource(this._client);

  Future<List<ChatMessage>> getMessages(String bookingId) async {
    final data = await _client
        .from('chat_messages')
        .select()
        .eq('booking_id', bookingId)
        .order('sent_at', ascending: true);
    return (data as List)
        .map((m) => ChatMessage.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<ChatMessage> sendMessage(String bookingId, String content) async {
    final data = await _client
        .from('chat_messages')
        .insert({
          'booking_id': bookingId,
          'sender_id': _client.auth.currentUser!.id,
          'content': content,
        })
        .select()
        .single();
    return ChatMessage.fromMap(data);
  }

  RealtimeChannel subscribe(
    String bookingId,
    void Function(ChatMessage) onMessage,
  ) {
    return _client
        .channel('chat:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (payload) =>
              onMessage(ChatMessage.fromMap(payload.newRecord)),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}

final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  return ChatRemoteDataSource(ref.read(supabaseClientProvider));
});
