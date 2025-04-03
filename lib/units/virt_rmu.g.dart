// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virt_rmu.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VirtRMUKeyboardAdapter extends TypeAdapter<VirtRMUKeyboard> {
  @override
  final int typeId = 41;

  @override
  VirtRMUKeyboard read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtRMUKeyboard()
      ..name = fields[0] as String?
      ..items = (fields[1] as List).cast<String?>();
  }

  @override
  void write(BinaryWriter writer, VirtRMUKeyboard obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.items);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtRMUKeyboardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VirtRMUInlineKeyboardAdapter extends TypeAdapter<VirtRMUInlineKeyboard> {
  @override
  final int typeId = 42;

  @override
  VirtRMUInlineKeyboard read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VirtRMUInlineKeyboard()
      ..name = fields[0] as String?
      ..items = (fields[1] as List).cast<MapEntry<String, String>?>();
  }

  @override
  void write(BinaryWriter writer, VirtRMUInlineKeyboard obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.items);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VirtRMUInlineKeyboardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
