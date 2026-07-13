// =============================================================================
// log_viewer_dialog.dart - Application Log Viewer / 应用日志查看器
// =============================================================================
// Date-based log browser with date range deletion. Reads logs from the Rust
// backend and displays them in a selectable text area.
//
// 按日期浏览和删除应用日志，从 Rust 后端读取并显示在可选中文本区域。
// =============================================================================

import 'package:flutter/material.dart';

import '../services/config_store.dart';
import '../services/i18n.dart';
import '../theme/colors.dart';

Future<void> showLogViewerDialogForContext({
  required BuildContext context,
  required ValueChanged<String> onMessage,
  required VoidCallback flushLogs,
}) async {
  String dateKey(DateTime value) => value.toIso8601String().substring(0, 10);

  flushLogs();
  var dates = ConfigStore.logDates();
  String? selectedDate = dates.isEmpty ? null : dates.first;
  String logText = selectedDate == null
      ? t('logs.noLogs')
      : ConfigStore.readLogsForDate(selectedDate);
  final logScrollController = ScrollController();

  try {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void scrollLogToTop() {
              if (!logScrollController.hasClients) {
                return;
              }
              logScrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              );
            }

            void scrollLogToBottom() {
              if (!logScrollController.hasClients) {
                return;
              }
              logScrollController.animateTo(
                logScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              );
            }

            Future<void> deleteLogRange() async {
              final now = DateTime.now();
              final parsedDates = dates
                  .map(DateTime.tryParse)
                  .whereType<DateTime>()
                  .toList();
              final firstDate = parsedDates.isEmpty
                  ? now.subtract(const Duration(days: 365))
                  : parsedDates.reduce((a, b) => a.isBefore(b) ? a : b);
              final lastDate = parsedDates.isEmpty
                  ? now
                  : parsedDates.reduce((a, b) => a.isAfter(b) ? a : b);
              final range = await showDateRangePicker(
                context: context,
                firstDate: firstDate,
                lastDate: lastDate.isBefore(now) ? now : lastDate,
                initialDateRange: DateTimeRange(
                  start: selectedDate == null
                      ? lastDate
                      : DateTime.tryParse(selectedDate!) ?? lastDate,
                  end: selectedDate == null
                      ? lastDate
                      : DateTime.tryParse(selectedDate!) ?? lastDate,
                ),
                helpText: t('logs.selectDeleteRange'),
              );
              if (range == null) {
                return;
              }
              final deleted = ConfigStore.deleteLogsByDateRange(
                dateKey(range.start),
                dateKey(range.end),
              );
              dates = ConfigStore.logDates();
              selectedDate = dates.contains(selectedDate)
                  ? selectedDate
                  : (dates.isEmpty ? null : dates.first);
              logText = selectedDate == null
                  ? t('logs.noLogs')
                  : ConfigStore.readLogsForDate(selectedDate!);
              setDialogState(() {});
              onMessage('${t('logs.deleted')}: $deleted');
            }

            return AlertDialog(
              title: Text(t('logs.title')),
              content: SizedBox(
                width: 760,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedDate,
                            decoration: InputDecoration(
                              labelText: t('logs.date'),
                              isDense: true,
                            ),
                            items: [
                              for (final date in dates)
                                DropdownMenuItem(
                                  value: date,
                                  child: Text(date),
                                ),
                            ],
                            onChanged: dates.isEmpty
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedDate = value;
                                      logText = ConfigStore.readLogsForDate(
                                        value,
                                      );
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (logScrollController.hasClients) {
                                            logScrollController.jumpTo(0);
                                          }
                                        });
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: logText.isEmpty ? null : scrollLogToTop,
                          icon: const Icon(Icons.vertical_align_top),
                          label: Text(t('logs.top')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: logText.isEmpty ? null : scrollLogToBottom,
                          icon: const Icon(Icons.vertical_align_bottom),
                          label: Text(t('logs.bottom')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: dates.isEmpty ? null : deleteLogRange,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(t('logs.deleteRange')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Theme.of(context).brightness == Brightness.dark
                            ? appDarkLevel8
                            : Colors.black,
                        child: Scrollbar(
                          controller: logScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: logScrollController,
                            child: SelectableText(
                              logText,
                              style: const TextStyle(
                                color: appDarkLevel3,
                                fontFamily: 'Consolas',
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('action.close')),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    logScrollController.dispose();
  }
}
