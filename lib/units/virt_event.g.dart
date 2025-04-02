// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virt_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VirtEventAdapter extends TypeAdapter<VirtEvent> {
  @override
  final int typeId = 200;

  @override
  VirtEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtEvent(
      type: fields[0] as VirtEventType,
      query: fields[1] as String,
    )..acts = (fields[2] as List).cast<VirtAct>();
  }

  @override
  void write(BinaryWriter writer, VirtEvent obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.query)
      ..writeByte(2)
      ..write(obj.acts);
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
