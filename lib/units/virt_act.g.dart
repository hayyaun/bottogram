// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virt_act.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VirtActAdapter extends TypeAdapter<VirtAct> {
  @override
  final int typeId = 2;

  @override
  VirtAct read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtAct(type: fields[0] as VirtActTypes, text: fields[1] as String);
  }

  @override
  void write(BinaryWriter writer, VirtAct obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.text);
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
