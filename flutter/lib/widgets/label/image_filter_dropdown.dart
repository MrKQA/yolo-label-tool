import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/annotation.dart';
import '../../models/shortcut.dart';
import '../../services/i18n.dart';
import '../../services/input_utils.dart';
import '../../services/path_utils.dart';
import '../../services/shortcut_runtime.dart';

const imageFilterAllValue = 'all';
const imageFilterUnlabeledValue = 'unlabeled';
const imageFilterClassPrefix = 'class:';

String imageFilterValueForClass(int classId) {
  return '$imageFilterClassPrefix$classId';
}

int? imageFilterClassId(String value) {
  if (!value.startsWith(imageFilterClassPrefix)) return null;
  return int.tryParse(value.substring(imageFilterClassPrefix.length));
}

String normalizeImageFilterValue(String value, List<LabelClass> labelClasses) {
  final classId = imageFilterClassId(value);
  if (classId == null) {
    return value == imageFilterUnlabeledValue
        ? imageFilterUnlabeledValue
        : imageFilterAllValue;
  }
  return labelClasses.any((item) => item.id == classId)
      ? value
      : imageFilterAllValue;
}

bool imageMatchesFilter({
  required ImageItem image,
  required String filterValue,
  required Map<String, List<AnnotationRegion>> annotationsByImage,
}) {
  final annotations =
      annotationsByImage[pathKey(image.path)] ?? const <AnnotationRegion>[];
  if (filterValue == imageFilterAllValue) return true;
  if (filterValue == imageFilterUnlabeledValue) return annotations.isEmpty;
  final classId = imageFilterClassId(filterValue);
  return classId != null &&
      annotations.any((annotation) => annotation.classId == classId);
}

class ImageFilterDropdown extends StatefulWidget {
  const ImageFilterDropdown({
    super.key,
    required this.images,
    required this.labelClasses,
    required this.annotationsByImage,
    required this.value,
    required this.onSelected,
    this.width,
    this.enabled = true,
    this.onConfirmShortcut,
  });

  final List<ImageItem> images;
  final List<LabelClass> labelClasses;
  final Map<String, List<AnnotationRegion>> annotationsByImage;
  final String value;
  final ValueChanged<String> onSelected;
  final double? width;
  final bool enabled;
  final VoidCallback? onConfirmShortcut;

  @override
  State<ImageFilterDropdown> createState() => _ImageFilterDropdownState();
}

class _ImageFilterDropdownState extends State<ImageFilterDropdown> {
  final TextEditingController _controller = TextEditingController();
  final MenuController _menuController = MenuController();
  late final FocusNode _focusNode;

  String get _value =>
      normalizeImageFilterValue(widget.value, widget.labelClasses);

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'image-filter-shortcut-scope',
      canRequestFocus: false,
      skipTraversal: true,
    );
    registerEditableFocusNode(_focusNode);
    _syncText();
  }

  @override
  void didUpdateWidget(covariant ImageFilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus) _syncText();
  }

  @override
  void dispose() {
    unregisterEditableFocusNode(_focusNode);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<DropdownMenuEntry<String>> _entries() {
    return [
      DropdownMenuEntry<String>(
        value: imageFilterAllValue,
        label: '${t('label.previewFilterAll')} (${widget.images.length})',
      ),
      DropdownMenuEntry<String>(
        value: imageFilterUnlabeledValue,
        label:
            '${t('label.previewFilterUnlabeled')} (${_unlabeledImageCount()})',
      ),
      for (final labelClass in widget.labelClasses)
        DropdownMenuEntry<String>(
          value: imageFilterValueForClass(labelClass.id),
          label: '${labelClass.name} (${_imageCountForClass(labelClass.id)})',
        ),
    ];
  }

  int _unlabeledImageCount() {
    return widget.images
        .where(
          (image) => imageMatchesFilter(
            image: image,
            filterValue: imageFilterUnlabeledValue,
            annotationsByImage: widget.annotationsByImage,
          ),
        )
        .length;
  }

  int _imageCountForClass(int classId) {
    final filterValue = imageFilterValueForClass(classId);
    return widget.images
        .where(
          (image) => imageMatchesFilter(
            image: image,
            filterValue: filterValue,
            annotationsByImage: widget.annotationsByImage,
          ),
        )
        .length;
  }

  String _labelForValue(String value) {
    final entries = _entries();
    for (final entry in entries) {
      if (entry.value == value) return entry.label;
    }
    return entries.first.label;
  }

  String _searchText(DropdownMenuEntry<String> entry) {
    if (entry.value == imageFilterAllValue) {
      return '${t('label.previewFilterAll')} all ${entry.label}';
    }
    if (entry.value == imageFilterUnlabeledValue) {
      return '${t('label.previewFilterUnlabeled')} unlabeled ${entry.label}';
    }
    final classId = imageFilterClassId(entry.value);
    for (final labelClass in widget.labelClasses) {
      if (labelClass.id == classId) return labelClass.name;
    }
    return entry.label;
  }

  String _normalizedSearch(String value) => value.trim().toLowerCase();

  List<DropdownMenuEntry<String>> _filterEntries(
    List<DropdownMenuEntry<String>> entries,
    String rawFilter,
  ) {
    final filter = _normalizedSearch(rawFilter);
    if (filter.isEmpty) return entries;
    return entries
        .where(
          (entry) => _normalizedSearch(_searchText(entry)).contains(filter),
        )
        .toList();
  }

  int? _searchEntry(List<DropdownMenuEntry<String>> entries, String rawQuery) {
    final query = _normalizedSearch(rawQuery);
    if (query.isEmpty) return null;
    final startsWithIndex = entries.indexWhere(
      (entry) => _normalizedSearch(_searchText(entry)).startsWith(query),
    );
    if (startsWithIndex >= 0) return startsWithIndex;
    final containsIndex = entries.indexWhere(
      (entry) => _normalizedSearch(_searchText(entry)).contains(query),
    );
    return containsIndex >= 0 ? containsIndex : null;
  }

  void _syncText({bool selectAll = false}) {
    final text = _labelForValue(_value);
    _controller.value = TextEditingValue(
      text: text,
      selection: selectAll
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleFocusChanged(bool focused) {
    if (!focused) {
      _syncText();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final enterPressed =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (enterPressed && _controller.text.trim().isEmpty) {
      widget.onSelected(imageFilterAllValue);
      _syncText(selectAll: true);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        ShortcutRuntime.matches(
          ShortcutAction.classNameAutocomplete,
          event.logicalKey,
        )) {
      _completeClassName();
      return KeyEventResult.handled;
    }
    final confirm = widget.onConfirmShortcut;
    if (event is KeyDownEvent &&
        confirm != null &&
        !_menuController.isOpen &&
        ShortcutRuntime.matches(
          ShortcutAction.dialogConfirm,
          event.logicalKey,
        )) {
      confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _completeClassName() {
    final query = _normalizedSearch(_controller.text);
    if (query.isEmpty) return false;
    final classEntries = _entries()
        .where((entry) => imageFilterClassId(entry.value) != null)
        .toList(growable: false);
    if (classEntries.isEmpty) return false;
    var index = classEntries.indexWhere(
      (entry) => _normalizedSearch(_searchText(entry)) == query,
    );
    index = index >= 0
        ? index
        : classEntries.indexWhere(
            (entry) => _normalizedSearch(_searchText(entry)).startsWith(query),
          );
    index = index >= 0
        ? index
        : classEntries.indexWhere(
            (entry) => _normalizedSearch(_searchText(entry)).contains(query),
          );
    if (index < 0) return false;
    final entry = classEntries[index];
    _controller.value = TextEditingValue(
      text: entry.label,
      selection: TextSelection.collapsed(offset: entry.label.length),
    );
    _menuController.close();
    widget.onSelected(entry.value);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _handleFocusChanged,
      onKeyEvent: _handleKeyEvent,
      child: DropdownMenu<String>(
        controller: _controller,
        menuController: _menuController,
        requestFocusOnTap: true,
        selectOnly: false,
        enabled: widget.enabled,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        width: widget.width,
        initialSelection: _value,
        textStyle: Theme.of(context).textTheme.labelSmall,
        enableFilter: true,
        enableSearch: true,
        filterCallback: _filterEntries,
        searchCallback: _searchEntry,
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        dropdownMenuEntries: _entries(),
        onSelected: (value) {
          if (value != null) widget.onSelected(value);
        },
      ),
    );
  }
}
