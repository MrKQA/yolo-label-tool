// =============================================================================
// navigation.dart - Top Menu Bar & Sidebar / 顶部菜单栏与侧边栏
// =============================================================================
// TopMenuBar: file/open/recent menu, import/export, undo/redo, settings, help.
// PrimarySidebar: collapsible section switcher (Label/Train/Browse/Database).
//
// TopMenuBar：文件/打开/最近菜单、导入导出、撤销/重做、设置、帮助。
// PrimarySidebar：可折叠的功能区切换器。
// =============================================================================

import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/colors.dart';
import '../../theme/dimensions.dart';
import '../../theme/theme_helpers.dart';

const _recentMenuVisibleCount = 5;

class TopMenuBar extends StatelessWidget {
  const TopMenuBar({
    super.key,
    required this.visible,
    required this.recentFolders,
    required this.recentFiles,
    required this.languageOptions,
    required this.activeLanguageCode,
    required this.projectActionsLocked,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenRecentFolder,
    required this.onOpenRecentFile,
    required this.onClearRecent,
    required this.onExit,
    required this.onImportDataset,
    required this.onExportDataset,
    required this.onShowTrainingHistory,
    required this.onUndo,
    required this.onRedo,
    required this.onCopy,
    required this.onPaste,
    required this.onShowSettings,
    required this.onShowLogs,
    required this.onShowHelp,
    required this.onShowAbout,
    required this.onProjectActionBlocked,
    required this.onLanguageSelected,
    required this.onPointerEnter,
    required this.onPointerExit,
  });

  final bool visible;
  final List<String> recentFolders;
  final List<String> recentFiles;
  final List<LanguageOption> languageOptions;
  final String activeLanguageCode;
  final bool projectActionsLocked;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final ValueChanged<String> onOpenRecentFolder;
  final ValueChanged<String> onOpenRecentFile;
  final VoidCallback onClearRecent;
  final VoidCallback onExit;
  final VoidCallback onImportDataset;
  final VoidCallback onExportDataset;
  final VoidCallback onShowTrainingHistory;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onShowSettings;
  final VoidCallback onShowLogs;
  final VoidCallback onShowHelp;
  final VoidCallback onShowAbout;
  final VoidCallback onProjectActionBlocked;
  final Future<void> Function(String code) onLanguageSelected;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;

  @override
  Widget build(BuildContext context) {
    final lockedColor = Theme.of(context).disabledColor;
    return MouseRegion(
      onEnter: (_) => onPointerEnter(),
      onHover: (_) => onPointerEnter(),
      onExit: (_) => onPointerExit(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: visible ? topMenuHeight : topMenuCollapsedHeight,
        decoration: BoxDecoration(
          color: panelColor(context),
          border: Border(bottom: BorderSide(color: borderColor(context))),
        ),
        child: ClipRect(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: visible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !visible,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Text(
                    t('app.title'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 16),
                  MenuBar(
                    style: MenuStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        panelColor(context),
                      ),
                      elevation: const WidgetStatePropertyAll(0),
                    ),
                    children: [
                      SubmenuButton(
                        menuChildren: [
                          MenuItemButton(
                            onPressed: _projectAction(onOpenFile),
                            leadingIcon: Icon(
                              Icons.image_outlined,
                              color: projectActionsLocked ? lockedColor : null,
                            ),
                            child: Text(
                              t('menu.openFile'),
                              style: _projectActionTextStyle(context),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: _projectAction(onOpenFolder),
                            leadingIcon: Icon(
                              Icons.folder_open,
                              color: projectActionsLocked ? lockedColor : null,
                            ),
                            child: Text(
                              t('menu.openFolder'),
                              style: _projectActionTextStyle(context),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: onShowTrainingHistory,
                            leadingIcon: const Icon(Icons.history),
                            child: Text(t('menu.trainingHistory')),
                          ),
                          _RecentFilesMenu(
                            recentFolders: recentFolders,
                            recentFiles: recentFiles,
                            projectActionsLocked: projectActionsLocked,
                            onOpenRecentFolder: onOpenRecentFolder,
                            onOpenRecentFile: onOpenRecentFile,
                            onProjectActionBlocked: onProjectActionBlocked,
                            onClearRecent: onClearRecent,
                          ),
                          const Divider(height: 1),
                          MenuItemButton(
                            onPressed: onExit,
                            leadingIcon: const Icon(Icons.exit_to_app),
                            child: Text(t('menu.exit')),
                          ),
                        ],
                        child: Text(t('menu.file')),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          MenuItemButton(
                            onPressed: _projectAction(onImportDataset),
                            leadingIcon: Icon(
                              Icons.upload_file,
                              color: projectActionsLocked ? lockedColor : null,
                            ),
                            child: Text(
                              t('menu.import'),
                              style: _projectActionTextStyle(context),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: onExportDataset,
                            leadingIcon: const Icon(Icons.file_download),
                            child: Text(t('menu.export')),
                          ),
                          const Divider(height: 1),
                          MenuItemButton(
                            onPressed: onUndo,
                            child: Text(t('menu.undo')),
                          ),
                          MenuItemButton(
                            onPressed: onRedo,
                            child: Text(t('menu.restore')),
                          ),
                          MenuItemButton(
                            onPressed: onCopy,
                            child: Text(t('menu.copy')),
                          ),
                          MenuItemButton(
                            onPressed: onPaste,
                            child: Text(t('menu.paste')),
                          ),
                        ],
                        child: Text(t('menu.edit')),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          SubmenuButton(
                            menuChildren: [
                              for (final language in languageOptions)
                                MenuItemButton(
                                  onPressed: () =>
                                      onLanguageSelected(language.code),
                                  leadingIcon:
                                      language.code == activeLanguageCode
                                      ? const Icon(Icons.check)
                                      : const SizedBox(width: 24),
                                  child: Text(language.label),
                                ),
                            ],
                            child: Text(t('settings.language')),
                          ),
                          MenuItemButton(
                            onPressed: onShowSettings,
                            leadingIcon: const Icon(Icons.settings_outlined),
                            child: Text(t('settings.preferences')),
                          ),
                          MenuItemButton(
                            onPressed: onShowLogs,
                            leadingIcon: const Icon(Icons.article_outlined),
                            child: Text(t('menu.viewLogs')),
                          ),
                          MenuItemButton(
                            onPressed: onShowSettings,
                            leadingIcon: const Icon(
                              Icons.delete_sweep_outlined,
                            ),
                            child: Text(t('settings.clearCache')),
                          ),
                        ],
                        child: Text(t('menu.settings')),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          MenuItemButton(
                            onPressed: onShowHelp,
                            child: Text(t('menu.shortcutHelp')),
                          ),
                          MenuItemButton(
                            onPressed: onShowAbout,
                            child: Text(t('menu.about')),
                          ),
                        ],
                        child: Text(t('menu.help')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback _projectAction(VoidCallback action) =>
      projectActionsLocked ? onProjectActionBlocked : action;

  TextStyle? _projectActionTextStyle(BuildContext context) =>
      projectActionsLocked
      ? TextStyle(color: Theme.of(context).disabledColor)
      : null;
}

class _RecentFilesMenu extends StatelessWidget {
  const _RecentFilesMenu({
    required this.recentFolders,
    required this.recentFiles,
    required this.projectActionsLocked,
    required this.onOpenRecentFolder,
    required this.onOpenRecentFile,
    required this.onProjectActionBlocked,
    required this.onClearRecent,
  });

  final List<String> recentFolders;
  final List<String> recentFiles;
  final bool projectActionsLocked;
  final ValueChanged<String> onOpenRecentFolder;
  final ValueChanged<String> onOpenRecentFile;
  final VoidCallback onProjectActionBlocked;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    final visibleFolders = recentFolders.take(_recentMenuVisibleCount).toList();
    final moreFolders = recentFolders.skip(_recentMenuVisibleCount).toList();
    final visibleFiles = recentFiles.take(_recentMenuVisibleCount).toList();
    final moreFiles = recentFiles.skip(_recentMenuVisibleCount).toList();
    final hasMoreItems = moreFolders.isNotEmpty || moreFiles.isNotEmpty;

    return SubmenuButton(
      menuChildren: [
        if (recentFolders.isEmpty)
          MenuItemButton(onPressed: null, child: Text(t('recent.noFolders')))
        else
          for (final folder in visibleFolders) _folderMenuItem(folder),
        const Divider(height: 1),
        if (recentFiles.isEmpty)
          MenuItemButton(onPressed: null, child: Text(t('recent.noFiles')))
        else
          for (final file in visibleFiles) _fileMenuItem(file),
        if (hasMoreItems) ...[
          const Divider(height: 1),
          SubmenuButton(
            menuChildren: [
              if (moreFolders.isNotEmpty) ...[
                MenuItemButton(
                  onPressed: null,
                  child: Text(t('recent.moreFolders')),
                ),
                for (final folder in moreFolders) _folderMenuItem(folder),
              ],
              if (moreFolders.isNotEmpty && moreFiles.isNotEmpty)
                const Divider(height: 1),
              if (moreFiles.isNotEmpty) ...[
                MenuItemButton(
                  onPressed: null,
                  child: Text(t('recent.moreFiles')),
                ),
                for (final file in moreFiles) _fileMenuItem(file),
              ],
            ],
            child: Text(t('recent.moreOptions')),
          ),
        ],
        const Divider(height: 1),
        MenuItemButton(
          onPressed: onClearRecent,
          child: Text(t('recent.clear')),
        ),
      ],
      child: Text(t('menu.openRecent')),
    );
  }

  MenuItemButton _folderMenuItem(String folder) {
    final onPressed = projectActionsLocked
        ? onProjectActionBlocked
        : () => onOpenRecentFolder(folder);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Builder(
        builder: (context) => Icon(
          Icons.folder_outlined,
          color: projectActionsLocked ? Theme.of(context).disabledColor : null,
        ),
      ),
      child: SizedBox(
        width: 260,
        child: Builder(
          builder: (context) => Text(
            folder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: projectActionsLocked
                ? TextStyle(color: Theme.of(context).disabledColor)
                : null,
          ),
        ),
      ),
    );
  }

  MenuItemButton _fileMenuItem(String file) {
    final onPressed = projectActionsLocked
        ? onProjectActionBlocked
        : () => onOpenRecentFile(file);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Builder(
        builder: (context) => Icon(
          Icons.image_outlined,
          color: projectActionsLocked ? Theme.of(context).disabledColor : null,
        ),
      ),
      child: SizedBox(
        width: 260,
        child: Builder(
          builder: (context) => Text(
            file,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: projectActionsLocked
                ? TextStyle(color: Theme.of(context).disabledColor)
                : null,
          ),
        ),
      ),
    );
  }
}

class PrimarySidebar extends StatelessWidget {
  const PrimarySidebar({
    super.key,
    required this.activeSection,
    required this.collapsed,
    required this.onCollapseChanged,
    required this.onSectionSelected,
  });

  final String activeSection;
  final bool collapsed;
  final ValueChanged<bool> onCollapseChanged;
  final ValueChanged<String> onSectionSelected;

  static const _sections = [
    _SectionSpec('label', Icons.edit_note, 'sidebar.label'),
    _SectionSpec('train', Icons.model_training, 'sidebar.train'),
    _SectionSpec('browse', Icons.photo_library_outlined, 'sidebar.browse'),
    _SectionSpec('crop', Icons.content_cut, 'sidebar.crop'),
    _SectionSpec('collaboration', Icons.groups_2_outlined, 'sidebar.collab'),
    _SectionSpec('database', Icons.storage_outlined, 'sidebar.database'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: collapsed ? collapsedSidebarWidth : expandedSidebarWidth,
      decoration: BoxDecoration(
        color: panelColor(context),
        border: Border(right: BorderSide(color: borderColor(context))),
      ),
      child: Column(
        children: [
          SizedBox(
            height: paneHeaderHeight,
            child: Center(
              child: Tooltip(
                message: collapsed
                    ? t('sidebar.expand')
                    : t('sidebar.collapse'),
                child: IconButton(
                  onPressed: () => onCollapseChanged(!collapsed),
                  icon: Icon(collapsed ? Icons.menu_open : Icons.menu),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          for (final section in _sections)
            _SidebarButton(
              section: section,
              collapsed: collapsed,
              selected: activeSection == section.id,
              onPressed: () => onSectionSelected(section.id),
            ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.section,
    required this.collapsed,
    required this.selected,
    required this.onPressed,
  });

  final _SectionSpec section;
  final bool collapsed;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : primaryTextColor(context);
    final background = selected
        ? (isDarkMode(context)
              ? appDarkControlBackground
              : const Color(0xFFEFF6FF))
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Tooltip(
        message: t(section.label),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  SizedBox(width: collapsed ? 0 : 12),
                  Icon(section.icon, color: foreground, size: 21),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(section.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionSpec {
  const _SectionSpec(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}
