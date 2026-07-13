import 'package:flutter/widgets.dart';

// =============================================================================
// dimensions.dart - Layout Dimensions / 布局尺寸常量
// =============================================================================
// Named constants for all fixed layout dimensions: pane widths/heights,
// workspace size, toolbar width, menu height, sidebar sizing, and margins.
//
// 所有固定布局尺寸的命名常量：面板宽高、工作区尺寸、工具栏宽度、菜单高度等。
// =============================================================================

const previewPaneWidth = 188.0;
const previewPaneMinWidth = 128.0;
const annotationWorkspaceWidth = 960.0;
const annotationWorkspaceHeight = 620.0;
const toolbarWidth = 184.0;
const topMenuHeight = 42.0;
const topMenuCollapsedHeight = 6.0;
const topMenuAutoHideDelay = Duration(seconds: 3);
const bottomBarHeight = 80.0;
const paneHeaderHeight = 52.0;
const previewPaneHeaderHeight = 64.0;
const expandedSidebarWidth = 112.0;
const collapsedSidebarWidth = 56.0;
const aiAssistPanelMinWidth = 320.0;
const aiAssistPanelMinHeight = 360.0;
const aiAssistPanelMaxWidth = 640.0;
const aiAssistPanelMaxHeight = 760.0;
const aiAssistPanelMargin = 12.0;

bool useCompactWorkspaceLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 1120 ||
    MediaQuery.sizeOf(context).height < 720;

double previewPaneWidthFor(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 900) return previewPaneMinWidth;
  if (width < 1120) return 144;
  if (width < 1500) return 168;
  if (width >= 2100) return 212;
  return previewPaneWidth;
}

double toolbarWidthFor(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 900) return 152;
  if (width < 1120) return 164;
  if (width < 1500) return 176;
  if (width >= 2100) return 204;
  return toolbarWidth;
}

double expandedSidebarWidthFor(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 900) return 88;
  if (width < 1280) return 100;
  if (width >= 2100) return 124;
  return expandedSidebarWidth;
}

double collapsedSidebarWidthFor(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 1120 ? 52 : collapsedSidebarWidth;

double bottomBarHeightFor(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  if (height < 720) return 62;
  if (height < 900) return 70;
  return bottomBarHeight;
}

double workspaceControlHeightFor(BuildContext context) =>
    MediaQuery.sizeOf(context).height < 720 ? 36 : 40;
