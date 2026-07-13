// =============================================================================
// image_preview_pane.dart - Image Preview Pane / 图片预览面板
// =============================================================================
// Left thumbnail strip with index input, class-based filter dropdown, and
// auto-scroll tracking for the selected image.
//
// 左侧缩略图列表：序号输入、按类别筛选下拉框和选中图片自动滚动跟踪。
// =============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/annotation.dart';
import '../../services/i18n.dart';
import '../../services/path_utils.dart';
import '../../theme/colors.dart';
import '../../theme/dimensions.dart';
import '../../theme/theme_helpers.dart';

class ImagePreviewPane extends StatefulWidget {
  const ImagePreviewPane({
    super.key,
    required this.images,
    required this.selectedIndex,
    required this.labelClasses,
    required this.annotationsByImage,
    required this.onImageSelected,
    required this.onContextMenu,
  });

  final List<ImageItem> images;
  final int selectedIndex;
  final List<LabelClass> labelClasses;
  final Map<String, List<AnnotationRegion>> annotationsByImage;
  final ValueChanged<int> onImageSelected;
  final Future<void> Function(TapDownDetails details, int? index) onContextMenu;

  @override
  State<ImagePreviewPane> createState() => _ImagePreviewPaneState();
}

class _ImagePreviewPaneState extends State<ImagePreviewPane> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _indexController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _indexFocusNode = FocusNode(debugLabel: 'preview-index');
  late final FocusNode _filterFocusNode;
  String _filterValue = _imagePreviewFilterAll;

  static const _imagePreviewFilterAll = 'all';
  static const _imagePreviewFilterUnlabeled = 'unlabeled';
  static const _imagePreviewClassPrefix = 'class:';

  @override
  void initState() {
    super.initState();
    _filterFocusNode = FocusNode(
      debugLabel: 'preview-filter',
      onKeyEvent: _handleFilterKeyEvent,
    );
    _filterFocusNode.addListener(_handleFilterFocusChanged);
    _syncIndexText();
    _syncFilterText();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollSelectedIntoView(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ImagePreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _normalizeFilter();
    _syncIndexText();
    if (!_filterFocusNode.hasFocus) {
      _syncFilterText();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_selectFirstVisibleEntryIfNeeded()) {
        return;
      }
      _scrollSelectedIntoView(
        animate: oldWidget.selectedIndex != widget.selectedIndex,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _indexController.dispose();
    _filterFocusNode.removeListener(_handleFilterFocusChanged);
    _filterFocusNode.dispose();
    _filterController.dispose();
    _indexFocusNode.dispose();
    super.dispose();
  }

  List<_ImagePreviewEntry> _filteredEntries() {
    final entries = <_ImagePreviewEntry>[];
    for (var index = 0; index < widget.images.length; index += 1) {
      final image = widget.images[index];
      if (_matchesFilter(image)) {
        entries.add(_ImagePreviewEntry(index: index, image: image));
      }
    }
    return entries;
  }

  bool _matchesFilter(ImageItem image) {
    final annotations =
        widget.annotationsByImage[pathKey(image.path)] ?? const [];
    if (_filterValue == _imagePreviewFilterAll) {
      return true;
    }
    if (_filterValue == _imagePreviewFilterUnlabeled) {
      return annotations.isEmpty;
    }
    if (_filterValue.startsWith(_imagePreviewClassPrefix)) {
      final classId = int.tryParse(
        _filterValue.substring(_imagePreviewClassPrefix.length),
      );
      return classId != null &&
          annotations.any((annotation) => annotation.classId == classId);
    }
    return true;
  }

  List<DropdownMenuEntry<String>> _filterEntries() {
    return [
      DropdownMenuEntry<String>(
        value: _imagePreviewFilterAll,
        label: '${t('label.previewFilterAll')} (${widget.images.length})',
      ),
      DropdownMenuEntry<String>(
        value: _imagePreviewFilterUnlabeled,
        label:
            '${t('label.previewFilterUnlabeled')} (${_countUnlabeledImages()})',
      ),
      for (final labelClass in widget.labelClasses)
        DropdownMenuEntry<String>(
          value: '$_imagePreviewClassPrefix${labelClass.id}',
          label: '${labelClass.name} (${_countImagesForClass(labelClass.id)})',
        ),
    ];
  }

  String _filterLabelForValue(String value) {
    if (value == _imagePreviewFilterAll) {
      return '${t('label.previewFilterAll')} (${widget.images.length})';
    }
    if (value == _imagePreviewFilterUnlabeled) {
      return '${t('label.previewFilterUnlabeled')} (${_countUnlabeledImages()})';
    }
    if (value.startsWith(_imagePreviewClassPrefix)) {
      final classId = int.tryParse(
        value.substring(_imagePreviewClassPrefix.length),
      );
      final labelClass = widget.labelClasses
          .where((item) => item.id == classId)
          .firstOrNull;
      if (labelClass != null) {
        return '${labelClass.name} (${_countImagesForClass(labelClass.id)})';
      }
    }
    return '${t('label.previewFilterAll')} (${widget.images.length})';
  }

  String _filterSearchTextForEntry(DropdownMenuEntry<String> entry) {
    if (entry.value == _imagePreviewFilterAll) {
      return '${t('label.previewFilterAll')} all ${entry.label}';
    }
    if (entry.value == _imagePreviewFilterUnlabeled) {
      return '${t('label.previewFilterUnlabeled')} unlabeled ${entry.label}';
    }
    if (entry.value.startsWith(_imagePreviewClassPrefix)) {
      final classId = int.tryParse(
        entry.value.substring(_imagePreviewClassPrefix.length),
      );
      final labelClass = widget.labelClasses
          .where((item) => item.id == classId)
          .firstOrNull;
      return labelClass == null ? entry.label : labelClass.name;
    }
    return entry.label;
  }

  String _normalizeFilterSearchText(String value) {
    return value.trim().toLowerCase();
  }

  List<DropdownMenuEntry<String>> _filterDropdownEntries(
    List<DropdownMenuEntry<String>> entries,
    String rawFilter,
  ) {
    final filter = _normalizeFilterSearchText(rawFilter);
    if (filter.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) => _normalizeFilterSearchText(
            _filterSearchTextForEntry(entry),
          ).contains(filter),
        )
        .toList();
  }

  int? _searchFilterDropdownEntry(
    List<DropdownMenuEntry<String>> entries,
    String rawQuery,
  ) {
    final query = _normalizeFilterSearchText(rawQuery);
    if (query.isEmpty) {
      return null;
    }
    final startsWithIndex = entries.indexWhere(
      (entry) => _normalizeFilterSearchText(
        _filterSearchTextForEntry(entry),
      ).startsWith(query),
    );
    if (startsWithIndex >= 0) {
      return startsWithIndex;
    }
    final containsIndex = entries.indexWhere(
      (entry) => _normalizeFilterSearchText(
        _filterSearchTextForEntry(entry),
      ).contains(query),
    );
    return containsIndex >= 0 ? containsIndex : null;
  }

  int _countUnlabeledImages() {
    var count = 0;
    for (final image in widget.images) {
      final annotations =
          widget.annotationsByImage[pathKey(image.path)] ?? const [];
      if (annotations.isEmpty) {
        count += 1;
      }
    }
    return count;
  }

  int _countImagesForClass(int classId) {
    var count = 0;
    for (final image in widget.images) {
      final annotations =
          widget.annotationsByImage[pathKey(image.path)] ?? const [];
      if (annotations.any((annotation) => annotation.classId == classId)) {
        count += 1;
      }
    }
    return count;
  }

  int _filteredPosition(List<_ImagePreviewEntry> entries) {
    final position = entries.indexWhere(
      (entry) => entry.index == widget.selectedIndex,
    );
    return position < 0 ? 0 : position + 1;
  }

  void _normalizeFilter() {
    if (!_filterValue.startsWith(_imagePreviewClassPrefix)) {
      return;
    }
    final classId = int.tryParse(
      _filterValue.substring(_imagePreviewClassPrefix.length),
    );
    final exists = widget.labelClasses.any((item) => item.id == classId);
    if (!exists) {
      _filterValue = _imagePreviewFilterAll;
    }
  }

  void _syncIndexText() {
    if (_indexFocusNode.hasFocus) {
      return;
    }
    final entries = _filteredEntries();
    _indexController.text = _filteredPosition(entries).toString();
  }

  void _syncFilterText({bool selectAll = false}) {
    final text = _filterLabelForValue(_filterValue);
    _filterController.value = TextEditingValue(
      text: text,
      selection: selectAll
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length),
    );
  }

  void _selectFilterTextNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_filterFocusNode.hasFocus) {
        return;
      }
      final text = _filterController.text;
      _filterController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    });
  }

  void _handleFilterFocusChanged() {
    if (_filterFocusNode.hasFocus) {
      _selectFilterTextNextFrame();
    } else {
      _syncFilterText();
    }
  }

  KeyEventResult _handleFilterKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (_filterController.text.trim().isNotEmpty) {
      return KeyEventResult.ignored;
    }
    _setFilter(_imagePreviewFilterAll, force: true);
    return KeyEventResult.handled;
  }

  void _commitIndex() {
    final entries = _filteredEntries();
    if (entries.isEmpty) {
      _indexController.text = '0';
      return;
    }
    final requested = int.tryParse(_indexController.text.trim());
    if (requested == null) {
      _syncIndexText();
      return;
    }
    final nextPosition = requested.clamp(1, entries.length).toInt();
    final nextIndex = entries[nextPosition - 1].index;
    _indexController.text = nextPosition.toString();
    widget.onImageSelected(nextIndex);
  }

  void _setFilter(String? value, {bool force = false}) {
    if (value == null) {
      return;
    }
    if (value == _filterValue && !force) {
      _syncFilterText(selectAll: _filterFocusNode.hasFocus);
      return;
    }
    setState(() => _filterValue = value);
    _syncFilterText(selectAll: _filterFocusNode.hasFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final entries = _filteredEntries();
      if (entries.isEmpty) {
        _syncIndexText();
        return;
      }
      if (!_selectFirstVisibleEntryIfNeeded()) {
        _syncIndexText();
        _scrollSelectedIntoView();
      }
    });
  }

  bool _selectFirstVisibleEntryIfNeeded() {
    if (_filterValue == _imagePreviewFilterAll) {
      return false;
    }
    final entries = _filteredEntries();
    if (entries.isEmpty ||
        entries.any((entry) => entry.index == widget.selectedIndex)) {
      return false;
    }
    widget.onImageSelected(entries.first.index);
    return true;
  }

  void _scrollSelectedIntoView({bool animate = true}) {
    if (!_scrollController.hasClients || widget.images.isEmpty) {
      return;
    }
    final entries = _filteredEntries();
    final filteredIndex = entries.indexWhere(
      (entry) => entry.index == widget.selectedIndex,
    );
    if (filteredIndex < 0) {
      return;
    }
    final viewport = _scrollController.position.viewportDimension;
    final tileExtent = _previewTileExtent(context);
    final targetTop = filteredIndex * tileExtent;
    final targetBottom = targetTop + tileExtent;
    final currentTop = _scrollController.offset;
    final currentBottom = currentTop + viewport;
    double? target;
    if (targetTop < currentTop) {
      target = targetTop;
    } else if (targetBottom > currentBottom) {
      target = targetBottom - viewport;
    }
    if (target == null) {
      return;
    }
    final clampedTarget = target
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    if (animate) {
      _scrollController.animateTo(
        clampedTarget,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(clampedTarget);
    }
  }

  double _previewTileExtent(BuildContext context) {
    final previewWidth = (MediaQuery.sizeOf(context).width * 0.22)
        .clamp(previewPaneMinWidth, previewPaneWidth)
        .toDouble();
    final tileWidth = math.max(80.0, previewWidth - 20);
    final imageHeight = math.max(72.0, (tileWidth - 12) * 0.75);
    return imageHeight + 48;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entries = _filteredEntries();
    final total = entries.length;
    final previewWidth = (MediaQuery.sizeOf(context).width * 0.22)
        .clamp(previewPaneMinWidth, previewPaneWidth)
        .toDouble();
    final tileExtent = _previewTileExtent(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => widget.onContextMenu(details, null),
      child: Container(
        width: previewWidth,
        decoration: BoxDecoration(
          color: appPanelColor(dark),
          border: Border(right: BorderSide(color: appBorderColor(dark))),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: TextField(
                          controller: _indexController,
                          focusNode: _indexFocusNode,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.go,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _commitIndex(),
                          onEditingComplete: _commitIndex,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '/ $total',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: Listener(
                      onPointerDown: (_) => _selectFilterTextNextFrame(),
                      child: DropdownMenu<String>(
                        key: ValueKey(_filterValue),
                        controller: _filterController,
                        focusNode: _filterFocusNode,
                        requestFocusOnTap: true,
                        width: previewWidth - 20,
                        initialSelection: _filterValue,
                        textStyle: Theme.of(context).textTheme.labelSmall,
                        enableFilter: true,
                        filterCallback: _filterDropdownEntries,
                        searchCallback: _searchFilterDropdownEntry,
                        inputDecorationTheme: const InputDecorationTheme(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        dropdownMenuEntries: _filterEntries(),
                        onSelected: _setFilter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(t('label.previewEmpty')))
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      interactive: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(10),
                        itemExtent: tileExtent,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _PreviewTile(
                            image: entry.image,
                            selected: entry.index == widget.selectedIndex,
                            onTap: () => widget.onImageSelected(entry.index),
                            onContextMenu: (details) =>
                                widget.onContextMenu(details, entry.index),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewEntry {
  const _ImagePreviewEntry({required this.index, required this.image});

  final int index;
  final ImageItem image;
}

/// 单张图片缩略图条目，支持选中和右键菜单。
/// Thumbnail item for one image with selection and context-menu support.
class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.image,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
  });

  final ImageItem image;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: onContextMenu,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? (dark
                      ? appDarkControlBackground
                      : const Color(0xFFEFF6FF))
                : appPanelColor(dark),
            border: Border.all(
              color: selected ? colorScheme.primary : appBorderColor(dark),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _ImagePreview(image: image)),
                const SizedBox(height: 6),
                Text(
                  image.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 缩略图图片渲染组件，图片损坏时显示占位图标。
/// Thumbnail renderer that shows a placeholder icon when loading fails.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image});

  final ImageItem image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.expand(
        child: Image.file(
          File(image.path),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFF94A3B8),
            child: Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
