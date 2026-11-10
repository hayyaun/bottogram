// Maintained Hive wire adapter. Existing type and field IDs are persistent data.
// Update explicitly with compatibility tests; do not renumber existing fields.

part of 'virt_event.dart';

class VirtEventAdapter extends TypeAdapter<VirtEvent> {
  @override
  final int typeId = 20;

  @override
  VirtEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtEvent(
        type: fields[0] as VirtEventType,
        query: fields[1] as String,
      )
      ..acts = (fields[2] as List).cast<VirtAct>()
      ..config =
          fields[3] == null ? {} : (fields[3] as Map).cast<String, dynamic>();
  }

  @override
  void write(BinaryWriter writer, VirtEvent obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.query)
      ..writeByte(2)
      ..write(obj.acts)
      ..writeByte(3)
      ..write(obj.config);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
