// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virt_rmu.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VirtRmuAdapter extends TypeAdapter<VirtRmu> {
  @override
  final int typeId = 3;

  @override
  VirtRmu read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtRmu()
      ..items = (fields[0] as List).cast<String?>()
      ..type = fields[1] as VirtRMUType;
  }

  @override
  void write(BinaryWriter writer, VirtRmu obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.items)
      ..writeByte(1)
      ..write(obj.type);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtRmuAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
