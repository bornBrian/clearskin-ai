enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;

  Map<String, Object?> toRow() => {
    'id': id,
    'role': role.name,
    'text': text,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory ChatMessage.fromRow(Map<String, Object?> r) => ChatMessage(
    id: r['id'] as String,
    role: ChatRole.values.byName(r['role'] as String),
    text: r['text'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );
}
