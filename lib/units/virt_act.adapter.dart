// Maintained Hive wire adapter. Existing type and field IDs are persistent data.
// Update explicitly with compatibility tests; do not renumber existing fields.

part of 'virt_act.dart';

class VirtActAdapter extends TypeAdapter<VirtAct> {
  @override
  final int typeId = 30;

  @override
  VirtAct read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtAct(type: fields[0] as VirtActType, text: fields[1] as String)
      ..rmu = fields[2] as VirtRMU?
      ..config =
          fields[3] == null ? {} : (fields[3] as Map).cast<String, dynamic>();
  }

  @override
  void write(BinaryWriter writer, VirtAct obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.rmu)
      ..writeByte(3)
      ..write(obj.config);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtActAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
