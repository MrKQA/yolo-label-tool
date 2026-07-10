extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNullValue {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
