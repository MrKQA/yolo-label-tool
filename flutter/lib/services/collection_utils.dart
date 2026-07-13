// =============================================================================
// collection_utils.dart - Collection Utilities / 集合工具
// =============================================================================
// Extension methods on Iterable providing firstOrNullValue and other
// convenience accessors used throughout the project.
//
// Iterable 扩展方法：提供 firstOrNullValue 等项目中常用的便捷访问器。
// =============================================================================

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNullValue {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
