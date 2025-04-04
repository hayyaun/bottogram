List<List<T>> splitListByNull<T>(List<T?> input) {
  List<List<T>> output = [];
  List<T> temp = [];

  for (var item in input) {
    if (item == null) {
      if (temp.isNotEmpty) {
        output.add(List.from(temp));
        temp.clear();
      }
    } else {
      temp.add(item);
    }
  }

  if (temp.isNotEmpty) {
    output.add(temp);
  }

  return output;
}

mixin Addable {
  dynamic operator +(dynamic other);
}

extension SumOnIterable on Iterable<int> {
  int sum() {
    return reduce((a, b) => a + b);
  }
}
