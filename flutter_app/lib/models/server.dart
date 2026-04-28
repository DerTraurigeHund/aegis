class Server {
  int? id;
  String name;
  String baseUrl;
  String apiKey;
  DateTime createdAt;

  Server({
    this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'base_url': baseUrl,
    'api_key': apiKey,
    'created_at': createdAt.toIso8601String(),
  };

  factory Server.fromMap(Map<String, dynamic> map) => Server(
    id: map['id'] as int?,
    name: map['name'] as String,
    baseUrl: map['base_url'] as String,
    apiKey: map['api_key'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
