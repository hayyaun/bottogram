// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virt_act.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VirtActAdapter extends TypeAdapter<VirtAct> {
  @override
  final int typeId = 30;

  @override
  VirtAct read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtAct(
      type: fields[1] as VirtActType,
      text: fields[2] as String,
      ev: fields[0] as VirtEvent,
    )..rmu = fields[3] as VirtRMU?;
  }

  @override
  void write(BinaryWriter writer, VirtAct obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.ev)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.rmu);
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
