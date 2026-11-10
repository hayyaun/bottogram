// Maintained Hive wire adapter. Existing type and field IDs are persistent data.
// Update explicitly with compatibility tests; do not renumber existing fields.

part of 'virt_bot.dart';

class VirtBotAdapter extends TypeAdapter<VirtBot> {
  @override
  final int typeId = 10;

  @override
  VirtBot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtBot(fields[0] as String, fields[1] as String)
      ..events = (fields[2] as List).cast<VirtEvent>();
  }

  @override
  void write(BinaryWriter writer, VirtBot obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.token)
      ..writeByte(2)
      ..write(obj.events);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtBotAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
