// =============================================================================
// ai_toolbar.dart - Label Page AI Toolbar / 标注页 AI 工具栏
// =============================================================================
// Right-side toolbar: drawing/selection tools, class list, annotation list panel,
// and AI assist panel toggle.
//
// 右侧工具栏：绘制/选择工具、类别列表、标注列表面板和 AI 辅助面板开关。
// =============================================================================

import 'package:flutter/material.dart';

import '../../models/annotation.dart';
import '../../services/i18n.dart';
import '../../theme/dimensions.dart';
import '../../theme/theme_helpers.dart';
import '../../widgets/label/tool_spec.dart';
import 'annotation_list_panel.dart';
import 'class_manager.dart';

/// Right-side AI/annotation toolbar with tools and class management.
class AiToolbar extends StatelessWidget {
  const AiToolbar({
    required this.activeTool,
    required this.activeClassId,
    required this.labelClasses,
    required this.annotations,
    required this.selectedAnnotationId,
    required this.showClassLabels,
    required this.aiPanelVisible,
    required this.classesEditable,
    required this.onToolSelected,
    required this.onClassSelected,
    required this.onClassAdded,
    required this.onClassEdited,
    required this.onClassColorChanged,
    required this.onClassDeleted,
    required this.onClassReordered,
    required this.onToggleClassLabels,
    required this.onAnnotationSelected,
    required this.onAnnotationClassChanged,
    required this.onAiConfigPressed,
  });

  final String activeTool;
  final int? activeClassId;
  final List<LabelClass> labelClasses;
  final List<AnnotationRegion> annotations;
  final String? selectedAnnotationId;
  final bool showClassLabels;
  final bool aiPanelVisible;
  final bool classesEditable;
  final ValueChanged<String> onToolSelected;
  final ValueChanged<int> onClassSelected;
  final VoidCallback onClassAdded;
  final ValueChanged<LabelClass> onClassEdited;
  final ValueChanged<LabelClass> onClassColorChanged;
  final ValueChanged<LabelClass> onClassDeleted;
  final void Function(int oldIndex, int newIndex) onClassReordered;
  final VoidCallback onToggleClassLabels;
  final ValueChanged<String?> onAnnotationSelected;
  final void Function(String annotationId, int classId)
  onAnnotationClassChanged;
  final VoidCallback onAiConfigPressed;

  static const _tools = [
    ToolSpec('select', Icons.near_me_outlined, 'tool.select'),
    ToolSpec('ai_config', Icons.auto_awesome, 'label.aiConfig'),
    ToolSpec('copy', Icons.copy_outlined, 'tool.copy'),
    ToolSpec('paste', Icons.content_paste_outlined, 'tool.paste'),
    ToolSpec('undo', Icons.undo, 'tool.undo'),
    ToolSpec('redo', Icons.redo, 'tool.redo'),
    ToolSpec('delete', Icons.delete_outline, 'tool.delete'),
    ToolSpec('export', Icons.file_download_outlined, 'tool.export'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showAnnotations =
        selectedAnnotationId != null || activeTool == 'annotations';
    return Container(
      width: toolbarWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: appPanelColor(dark),
        border: Border(left: BorderSide(color: appBorderColor(dark))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showAnnotations ? t('label.annotations') : t('label.ai'),
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: showAnnotations
                      ? t('label.showTools')
                      : t('label.showAnnotations'),
                  child: IconButton(
                    onPressed: () => onToolSelected(
                      showAnnotations ? 'select' : 'annotations',
                    ),
                    icon: Icon(
                      showAnnotations
                          ? Icons.construction_outlined
                          : Icons.format_list_bulleted,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (showAnnotations)
            Expanded(
              child: AnnotationListPanel(
                annotations: annotations,
                labelClasses: labelClasses,
                selectedAnnotationId: selectedAnnotationId,
                onAnnotationSelected: onAnnotationSelected,
                onAnnotationClassChanged: onAnnotationClassChanged,
              ),
            )
          else ...[
            for (final tool in _tools)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: _ToolButton(
                  tool: tool,
                  selected: tool.id == 'ai_config'
                      ? aiPanelVisible
                      : tool.id == activeTool,
                  onPressed: () {
                    if (tool.id == 'ai_config') {
                      onAiConfigPressed();
                    } else {
                      onToolSelected(tool.id);
                    }
                  },
                ),
              ),
            const Divider(height: 16),
            Expanded(
              child: ClassManager(
                activeClassId: activeClassId,
                labelClasses: labelClasses,
                showClassLabels: showClassLabels,
                classesEditable: classesEditable,
                onClassSelected: onClassSelected,
                onClassAdded: onClassAdded,
                onClassEdited: onClassEdited,
                onClassColorChanged: onClassColorChanged,
                onClassDeleted: onClassDeleted,
                onClassReordered: onClassReordered,
                onToggleClassLabels: onToggleClassLabels,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 工具栏按钮，负责图标、文字和选中态显示。
/// Toolbar button that renders icon, text, and selected state.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onPressed,
  });

  final ToolSpec tool;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? colorScheme.primaryContainer
        : appControlColor(dark);
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : appTextColor(dark);

    return Tooltip(
      message: t(tool.label),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? colorScheme.primary : appBorderColor(dark),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(tool.icon, size: 19, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t(tool.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
