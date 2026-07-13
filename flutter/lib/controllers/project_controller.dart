// =============================================================================
// project_controller.dart - Annotation Project State / 标注项目状态管理
// =============================================================================
// Owns the current annotation project: images, label classes, annotation
// regions, undo/redo stacks, and editing serials.
//
// 管理当前标注项目：图片列表、类别、标注区域、撤销/重做栈、编辑序列号。
// =============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/annotation.dart';
import '../models/imported_dataset.dart';
import '../services/annotation_database_codec.dart';
import '../services/path_utils.dart';

/// Owns the currently opened annotation project and its editing history.
class ProjectController extends ChangeNotifier {
  final List<ImageItem> images = [];
  final List<LabelClass> labelClasses = [];
  final Map<String, List<AnnotationRegion>> annotationsByImage = {};
  final Map<String, String> imageSplits = {};
  final Map<String, Size> imageDisplaySizes = {};
  final List<List<AnnotationRegion>> undoStack = [];
  final List<List<AnnotationRegion>> redoStack = [];

  int selectedImageIndex = 0;
  String? selectedAnnotationId;
  int? activeClassId;
  int classSerial = 1;
  int annotationSerial = 1;
  AnnotationRegion? copiedAnnotation;
  Size? imageDisplaySize;
  ImportedDataset? importedDataset;

  ImageItem? get selectedImage {
    if (images.isEmpty) {
      return null;
    }
    return images[selectedImageIndex.clamp(0, images.length - 1)];
  }

  String? get selectedImageKey {
    final image = selectedImage;
    return image == null ? null : pathKey(image.path);
  }

  List<AnnotationRegion> get currentAnnotations {
    final key = selectedImageKey;
    if (key == null) {
      return const [];
    }
    return annotationsByImage[key] ?? const [];
  }

  String get selectedImageSplit {
    final key = selectedImageKey;
    return key == null ? 'train' : imageSplits[key] ?? 'train';
  }

  List<AnnotationRegion> annotationsForPath(String path) {
    return annotationsByImage[pathKey(path)] ?? const [];
  }

  Size? displaySizeForPath(String path) {
    final key = pathKey(path);
    return imageDisplaySizes[key] ?? imageDisplaySizes[path];
  }

  int imageIndexOfPath(String path) {
    final key = pathKey(path);
    return images.indexWhere((image) => pathKey(image.path) == key);
  }

  void clear() {
    images.clear();
    labelClasses.clear();
    annotationsByImage.clear();
    imageSplits.clear();
    imageDisplaySizes.clear();
    undoStack.clear();
    redoStack.clear();
    selectedImageIndex = 0;
    selectedAnnotationId = null;
    activeClassId = null;
    classSerial = 1;
    annotationSerial = 1;
    copiedAnnotation = null;
    imageDisplaySize = null;
    importedDataset = null;
    notifyListeners();
  }

  void clearAnnotationData() {
    labelClasses.clear();
    annotationsByImage.clear();
    imageSplits.clear();
    importedDataset = null;
    clearHistory();
    activeClassId = null;
    selectedAnnotationId = null;
    classSerial = 1;
    annotationSerial = 1;
    notifyListeners();
  }

  void openSingleImage(String path) {
    _clearForReplacement();
    images.add(ImageItem.fromPath(path));
    imageSplits[pathKey(path)] = 'train';
    notifyListeners();
  }

  void openImages(Iterable<String> paths) {
    _clearForReplacement();
    images.addAll(paths.map(ImageItem.fromPath));
    notifyListeners();
  }

  int insertImages(List<String> paths, {int? insertAfterIndex}) {
    final newPaths = paths
        .where((path) => imageIndexOfPath(path) < 0)
        .toList(growable: false);
    if (newPaths.isEmpty) {
      return 0;
    }
    final insertIndex = insertAfterIndex == null
        ? images.length
        : (insertAfterIndex + 1).clamp(0, images.length);
    images.insertAll(insertIndex, newPaths.map(ImageItem.fromPath));
    for (final path in newPaths) {
      imageSplits.putIfAbsent(pathKey(path), () => 'train');
    }
    selectedImageIndex = insertIndex;
    selectedAnnotationId = null;
    clearHistory();
    notifyListeners();
    return newPaths.length;
  }

  ImageItem? deleteImage(int index) {
    if (index < 0 || index >= images.length) {
      return null;
    }
    final removed = images.removeAt(index);
    final key = pathKey(removed.path);
    imageSplits.remove(key);
    annotationsByImage.remove(key);
    imageDisplaySizes.remove(key);
    selectedImageIndex = images.isEmpty
        ? 0
        : selectedImageIndex.clamp(0, images.length - 1);
    selectedAnnotationId = null;
    clearHistory();
    notifyListeners();
    return removed;
  }

  bool selectImage(int index) {
    if (index < 0 || index >= images.length) {
      return false;
    }
    selectedImageIndex = index;
    selectedAnnotationId = null;
    clearHistory();
    notifyListeners();
    return true;
  }

  bool setSelectedImageSplit(String split, Set<String> validSplits) {
    final key = selectedImageKey;
    if (key == null || !validSplits.contains(split)) {
      return false;
    }
    imageSplits[key] = split;
    notifyListeners();
    return true;
  }

  void pushAnnotationSnapshot({int limit = 50}) {
    undoStack.add(List<AnnotationRegion>.of(currentAnnotations));
    if (undoStack.length > limit) {
      undoStack.removeAt(0);
    }
    redoStack.clear();
  }

  bool undoAnnotations() {
    if (undoStack.isEmpty) {
      return false;
    }
    final snapshot = undoStack.removeLast();
    redoStack.add(List<AnnotationRegion>.of(currentAnnotations));
    _restoreCurrentAnnotations(snapshot);
    notifyListeners();
    return true;
  }

  bool redoAnnotations() {
    if (redoStack.isEmpty) {
      return false;
    }
    final snapshot = redoStack.removeLast();
    undoStack.add(List<AnnotationRegion>.of(currentAnnotations));
    _restoreCurrentAnnotations(snapshot);
    notifyListeners();
    return true;
  }

  void clearHistory() {
    undoStack.clear();
    redoStack.clear();
  }

  LabelClass? classById(int id) {
    for (final labelClass in labelClasses) {
      if (labelClass.id == id) {
        return labelClass;
      }
    }
    return null;
  }

  void addLabelClass(LabelClass labelClass) {
    labelClasses.add(labelClass);
    activeClassId = labelClass.id;
    notifyListeners();
  }

  bool selectLabelClass(int classId) {
    if (classById(classId) == null) {
      return false;
    }
    activeClassId = classId;
    notifyListeners();
    return true;
  }

  bool updateLabelClass(LabelClass labelClass) {
    final index = labelClasses.indexWhere((item) => item.id == labelClass.id);
    if (index < 0) {
      return false;
    }
    labelClasses[index] = labelClass;
    notifyListeners();
    return true;
  }

  bool deleteLabelClass(int classId) {
    final previousLength = labelClasses.length;
    labelClasses.removeWhere((item) => item.id == classId);
    if (labelClasses.length == previousLength) {
      return false;
    }
    for (final annotations in annotationsByImage.values) {
      annotations.removeWhere((annotation) => annotation.classId == classId);
    }
    if (activeClassId == classId) {
      activeClassId = labelClasses.isEmpty ? null : labelClasses.first.id;
    }
    selectedAnnotationId = null;
    notifyListeners();
    return true;
  }

  bool reorderLabelClass(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= labelClasses.length ||
        newIndex < 0 ||
        newIndex >= labelClasses.length ||
        oldIndex == newIndex) {
      return false;
    }
    final item = labelClasses.removeAt(oldIndex);
    labelClasses.insert(newIndex, item);
    notifyListeners();
    return true;
  }

  String nextAnnotationId() => 'ann_${annotationSerial++}';

  void recalculateAnnotationSerial() {
    annotationSerial = nextAnnotationSerialFor(annotationsByImage);
  }

  AnnotationRegion? annotationById(String id) {
    for (final annotation in currentAnnotations) {
      if (annotation.id == id) {
        return annotation;
      }
    }
    return null;
  }

  bool selectAnnotation(String? id) {
    final annotation = id == null ? null : annotationById(id);
    if (id != null && annotation == null) {
      return false;
    }
    selectedAnnotationId = id;
    if (annotation != null) {
      activeClassId = annotation.classId;
    }
    notifyListeners();
    return true;
  }

  bool addAnnotation(AnnotationRegion annotation, {String? imagePath}) {
    final key = imagePath == null ? selectedImageKey : pathKey(imagePath);
    if (key == null) {
      return false;
    }
    annotationsByImage.putIfAbsent(key, () => []).add(annotation);
    notifyListeners();
    return true;
  }

  int addAnnotations(String imagePath, Iterable<AnnotationRegion> annotations) {
    final additions = annotations.toList(growable: false);
    if (additions.isEmpty) {
      return 0;
    }
    annotationsByImage
        .putIfAbsent(pathKey(imagePath), () => [])
        .addAll(additions);
    notifyListeners();
    return additions.length;
  }

  int replaceGeneratedAnnotations({
    required String imagePath,
    required Set<String> removeIds,
    required Iterable<AnnotationRegion> additions,
  }) {
    final next = additions.toList(growable: false);
    final annotations = annotationsByImage.putIfAbsent(
      pathKey(imagePath),
      () => [],
    );
    if (removeIds.isNotEmpty) {
      annotations.removeWhere(
        (annotation) => removeIds.contains(annotation.id),
      );
    }
    annotations.addAll(next);
    if (removeIds.isNotEmpty || next.isNotEmpty) {
      notifyListeners();
    }
    return next.length;
  }

  bool updateAnnotation(AnnotationRegion annotation) {
    final index = currentAnnotations.indexWhere(
      (item) => item.id == annotation.id,
    );
    if (index < 0) {
      return false;
    }
    currentAnnotations[index] = annotation;
    notifyListeners();
    return true;
  }

  bool changeAnnotationClass(String annotationId, int classId) {
    final annotation = annotationById(annotationId);
    if (annotation == null) {
      return false;
    }
    final index = currentAnnotations.indexOf(annotation);
    currentAnnotations[index] = annotation.copyWith(classId: classId);
    activeClassId = classId;
    notifyListeners();
    return true;
  }

  AnnotationRegion? deleteAnnotation(String id) {
    final annotation = annotationById(id);
    if (annotation == null) {
      return null;
    }
    currentAnnotations.remove(annotation);
    if (selectedAnnotationId == id) {
      selectedAnnotationId = null;
    }
    notifyListeners();
    return annotation;
  }

  AnnotationRegion? copySelectedAnnotation() {
    final id = selectedAnnotationId;
    final annotation = id == null ? null : annotationById(id);
    if (annotation == null) {
      return null;
    }
    copiedAnnotation = annotation;
    return annotation;
  }

  AnnotationRegion? pasteCopiedAnnotation({
    required String authorId,
    required String authorName,
    required int authorColorValue,
  }) {
    final copied = copiedAnnotation;
    if (selectedImageKey == null || copied == null) {
      return null;
    }
    final pasted = copied
        .duplicate(nextAnnotationId())
        .copyWith(
          authorId: authorId,
          authorName: authorName,
          authorColorValue: authorColorValue,
        );
    annotationsByImage.putIfAbsent(selectedImageKey!, () => []).add(pasted);
    selectedAnnotationId = pasted.id;
    notifyListeners();
    return pasted;
  }

  void applyAnnotationSnapshot({
    required String imagePath,
    required List<AnnotationRegion> incoming,
    required bool authoritative,
    required Set<String> scopedAuthors,
  }) {
    final annotations = annotationsByImage.putIfAbsent(
      pathKey(imagePath),
      () => [],
    );
    final incomingIds = {for (final item in incoming) item.id};
    if (authoritative) {
      annotations.removeWhere((item) => !incomingIds.contains(item.id));
    } else if (scopedAuthors.isNotEmpty) {
      annotations.removeWhere(
        (item) =>
            scopedAuthors.contains(item.authorId) &&
            !incomingIds.contains(item.id),
      );
    }
    for (final annotation in incoming) {
      final index = annotations.indexWhere((item) => item.id == annotation.id);
      if (index >= 0) {
        annotations[index] = annotation;
      } else {
        annotations.add(annotation);
      }
    }
    notifyListeners();
  }

  void replaceLabelClasses(Iterable<LabelClass> classes) {
    labelClasses
      ..clear()
      ..addAll(classes);
    var maxClassId = -1;
    for (final labelClass in labelClasses) {
      if (labelClass.id > maxClassId) {
        maxClassId = labelClass.id;
      }
    }
    final nextClassSerial = maxClassId + 1;
    if (nextClassSerial > classSerial) {
      classSerial = nextClassSerial;
    }
    if (labelClasses.isEmpty) {
      activeClassId = null;
    } else if (activeClassId == null || classById(activeClassId!) == null) {
      activeClassId = labelClasses.first.id;
    }
    notifyListeners();
  }

  void applyProjectSnapshot({
    required List<ImageItem> images,
    required Map<String, String> splits,
    required Map<String, Size> displaySizes,
    required List<LabelClass> classes,
    required Map<String, List<AnnotationRegion>> annotations,
    required int selectedIndex,
    required int nextClassSerial,
    required int nextAnnotationSerial,
  }) {
    this.images
      ..clear()
      ..addAll(images);
    imageSplits
      ..clear()
      ..addAll(splits);
    imageDisplaySizes
      ..clear()
      ..addAll(displaySizes);
    labelClasses
      ..clear()
      ..addAll(classes);
    annotationsByImage
      ..clear()
      ..addAll(annotations);
    importedDataset = null;
    selectedImageIndex = selectedIndex;
    selectedAnnotationId = null;
    activeClassId = classes.isEmpty ? null : classes.first.id;
    if (nextClassSerial > classSerial) {
      classSerial = nextClassSerial;
    }
    if (nextAnnotationSerial > annotationSerial) {
      annotationSerial = nextAnnotationSerial;
    }
    clearHistory();
    notifyListeners();
  }

  void applyImportedDataset({
    required List<ImageItem> images,
    required List<LabelClass> classes,
    required Map<String, List<AnnotationRegion>> annotations,
    required Map<String, String> splits,
    required ImportedDataset dataset,
    required int nextClassSerial,
    required int nextAnnotationSerial,
  }) {
    this.images
      ..clear()
      ..addAll(images);
    labelClasses
      ..clear()
      ..addAll(classes);
    annotationsByImage
      ..clear()
      ..addAll(annotations);
    imageSplits
      ..clear()
      ..addAll(splits);
    importedDataset = dataset;
    classSerial = nextClassSerial;
    annotationSerial = nextAnnotationSerial;
    activeClassId = classes.isEmpty ? null : classes.first.id;
    selectedImageIndex = 0;
    selectedAnnotationId = null;
    copiedAnnotation = null;
    imageDisplaySize = null;
    clearHistory();
    notifyListeners();
  }

  void applyLoadedAnnotations({
    required List<LabelClass> classes,
    required Map<String, List<AnnotationRegion>> loadedAnnotations,
  }) {
    labelClasses
      ..clear()
      ..addAll(classes);
    var maxClassId = -1;
    for (final labelClass in labelClasses) {
      if (labelClass.id > maxClassId) {
        maxClassId = labelClass.id;
      }
    }
    classSerial = maxClassId + 1;
    activeClassId = labelClasses.isEmpty ? null : labelClasses.first.id;
    for (final image in images) {
      final key = pathKey(image.path);
      final annotations = loadedAnnotations[key];
      if (annotations == null || annotations.isEmpty) {
        annotationsByImage.remove(key);
      } else {
        annotationsByImage[key] = List<AnnotationRegion>.of(annotations);
      }
    }
    recalculateAnnotationSerial();
    selectedAnnotationId = null;
    clearHistory();
    notifyListeners();
  }

  void _restoreCurrentAnnotations(List<AnnotationRegion> snapshot) {
    final key = selectedImageKey;
    if (key == null) {
      return;
    }
    annotationsByImage[key] = List<AnnotationRegion>.of(snapshot);
    if (selectedAnnotationId != null &&
        !currentAnnotations.any(
          (annotation) => annotation.id == selectedAnnotationId,
        )) {
      selectedAnnotationId = null;
    }
  }

  void _clearForReplacement() {
    images.clear();
    labelClasses.clear();
    annotationsByImage.clear();
    imageSplits.clear();
    imageDisplaySizes.clear();
    selectedImageIndex = 0;
    selectedAnnotationId = null;
    activeClassId = null;
    classSerial = 1;
    annotationSerial = 1;
    copiedAnnotation = null;
    imageDisplaySize = null;
    importedDataset = null;
    clearHistory();
  }
}
