import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:friend_private/backend/http/api/memories.dart';
import 'package:friend_private/backend/schema/memory.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

enum BottomSheetView { share, exportTranscript, exportSummary }

enum ExportType { txt, pdf, markdown }

void _copyTranscript(BuildContext context, ServerMemory memory) {
  Clipboard.setData(ClipboardData(text: memory.getTranscript(generate: true)));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Transcript copied to clipboard')),
  );
  HapticFeedback.lightImpact();
}

void _copySummary(BuildContext context, ServerMemory memory) {
  final summary = memory.structured.toString();
  Clipboard.setData(ClipboardData(text: summary));
  HapticFeedback.lightImpact();

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Summary copied to clipboard')),
  );
}

const String header = "GENERATED BY FRIEND, basedhardware.com\n\n";

void _exportPDF(ServerMemory memory, bool isTranscript) async {
  final pdf = pw.Document();

  final structured = memory.structured;

  if (isTranscript) {
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Transcript Export', style: const pw.TextStyle(fontSize: 20)),
            pw.SizedBox(height: 12),
            pw.Text(memory.getTranscript(generate: true), style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 12),
          ],
        ),
      ),
    );
  } else {
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Memory Export', style: const pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 12),
            pw.Text('Title: ${structured.title}', style: const pw.TextStyle(fontSize: 18)),
            pw.SizedBox(height: 12),
            pw.Text('Overview', style: const pw.TextStyle(fontSize: 18)),
            pw.Text(structured.overview),
            pw.SizedBox(height: 12),
            pw.Text('Action Items', style: const pw.TextStyle(fontSize: 18)),
            ...structured.actionItems.map((e) => pw.Text('- ${e.description}')),
            pw.SizedBox(height: 12),
            pw.Text('Summary', style: const pw.TextStyle(fontSize: 18)),
            pw.Text(structured.overview),
          ],
        ),
      ),
    );
  }

  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/memory_export.pdf');
  await file.writeAsBytes(await pdf.save());

  await Share.shareXFiles([XFile(file.path)], text: header);
}

void _exportTranscriptTxt(ServerMemory memory) async {
  final directory = await getApplicationDocumentsDirectory();
  final transcriptFile = File('${directory.path}/memory_transcript.txt');
  final transcript = "$header${memory.getTranscript(generate: true)}";
  await transcriptFile.writeAsString(transcript);

  await Share.shareXFiles([XFile(transcriptFile.path)], text: header);
}

void _exportSummaryTxt(ServerMemory memory) async {
  final directory = await getApplicationDocumentsDirectory();
  final summaryFile = File('${directory.path}/summary.txt');
  await summaryFile.writeAsString("$header${memory.structured.toString()}");
  await Share.shareXFiles([XFile(summaryFile.path)], text: header);
}

void _exportSummaryMarkdown(ServerMemory memory) async {
  final directory = await getApplicationDocumentsDirectory();
  final markdownFile = File('${directory.path}/memory_export.md');
  final structured = memory.structured;
  final markdown = """
    # Summary Export

    ## Title: ${structured.title}


    ### Action Items
    ${structured.actionItems.map((e) => '- ${e.description}').join('\n')}

    ### summary
    ${memory.structured.overview}
    """
      .replaceAll('    ', '');
  await markdownFile.writeAsString(markdown);

  await Share.shareXFiles([XFile(markdownFile.path)], text: header);
}

void showShareBottomSheet(
  BuildContext context,
  ServerMemory memory,
  StateSetter setState,
) async {
  BottomSheetView currentView = BottomSheetView.share;
  ExportType? exportType;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          void updateView(BottomSheetView view) {
            setModalState(() {
              currentView = view;
              debugPrint("View Set to: ${view.name}");
            });
          }

          void setExportType(ExportType type) {
            setModalState(() {
              exportType = type;
              debugPrint("Type Set to: ${type.name}");
            });
          }

          debugPrint("Current View: $currentView");

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentView == BottomSheetView.share) ...[
                  ListTile(
                    title: Text(
                      memory.discarded ? 'Discarded Memory' : memory.structured.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    leading: const Icon(Icons.description),
                    trailing: IconButton(
                      icon: const Icon(Icons.cancel_outlined),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    child: Column(
                      children: [
                        _buildListTile(
                          context,
                          title: 'Copy URL',
                          icon: Icons.link,
                          onTap: () async {
                            // TODO: include loading indicator
                            bool shared = await setMemoryVisibility(memory.id);
                            if (!shared) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Memory URL could not be shared.')),
                              );
                              return;
                            }
                            // print('https://omitdotme.web.app/memories/${memory.id}');
                            Clipboard.setData(ClipboardData(text: 'https://omitdotme.web.app/memories/${memory.id}'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('URL Copied to Clipboard')),
                            );
                            Navigator.pop(ctx);
                            HapticFeedback.lightImpact();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    child: Column(
                      children: [
                        _buildListTile(
                          context,
                          title: 'Copy Transcript',
                          icon: Icons.copy,
                          onTap: () => {Navigator.pop(ctx), _copyTranscript(context, memory)},
                        ),
                        memory.discarded
                            ? const SizedBox.shrink()
                            : _buildListTile(
                                context,
                                title: 'Copy Summary',
                                icon: Icons.file_copy,
                                onTap: () => {Navigator.pop(ctx), _copySummary(context, memory)},
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    shape: memory.discarded
                        ? null
                        : const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    child: Column(
                      children: [
                        _buildListTile(
                          context,
                          title: 'Export Transcript',
                          icon: Icons.description,
                          onTap: () {
                            updateView(BottomSheetView.exportTranscript);
                          },
                        ),
                        memory.discarded
                            ? const SizedBox.shrink()
                            : _buildListTile(
                                context,
                                title: 'Export Summary',
                                icon: Icons.summarize,
                                onTap: () => updateView(BottomSheetView.exportSummary),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10)
                ] else if (currentView == BottomSheetView.exportTranscript) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text('Export Transcript', style: Theme.of(context).textTheme.labelLarge),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        onPressed: () => updateView(BottomSheetView.share),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.text_snippet),
                          title: const Text('TXT'),
                          trailing: SizedBox(
                              width: 60,
                              child: exportType == ExportType.txt ? const Icon(Icons.check_outlined) : Container()),
                          onTap: () => setExportType(ExportType.txt),
                        ),
                        // FIXME ~ is not working ~ helvetica issue
                        // ListTile(
                        //   leading: const Icon(Icons.picture_as_pdf),
                        //   title: const Text('PDF'),
                        //   trailing: SizedBox(
                        //       width: 60,
                        //       child: exportType == ExportType.pdf ? const Icon(Icons.check_outlined) : Container()),
                        //   onTap: () => setExportType(ExportType.pdf),
                        // ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () {
                        switch (exportType) {
                          case ExportType.pdf:
                            _exportPDF(memory, true);
                            break;
                          case ExportType.txt:
                            _exportTranscriptTxt(memory);
                            break;
                          default:
                            // _fullExport(memory, context, true);
                            break;
                        }
                      },
                      child: Text('Export', style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ),
                ] else if (currentView == BottomSheetView.exportSummary) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text('Export Summary', style: Theme.of(context).textTheme.labelLarge),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        onPressed: () => updateView(BottomSheetView.share),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Container(
                  //   alignment: Alignment.centerLeft,
                  //   child: Text(
                  //     'Export as',
                  //     style: Theme.of(context).textTheme.bodySmall,
                  //   ),
                  // ),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.text_snippet),
                          title: const Text('TXT'),
                          onTap: () => setExportType(ExportType.txt),
                          trailing: SizedBox(
                            width: 60,
                            child: exportType == ExportType.txt ? const Icon(Icons.check_outlined) : null,
                          ),
                        ),
                        // FIXME markdown export not working
                        // ListTile(
                        //   leading: const Icon(Icons.subtitles),
                        //   title: const Text('Markdown'),
                        //   onTap: () => setExportType(ExportType.markdown),
                        //   trailing: SizedBox(
                        //     width: 60,
                        //     child: exportType == ExportType.markdown ? const Icon(Icons.check_outlined) : null,
                        //   ),
                        // ),
                        ListTile(
                          leading: const Icon(Icons.picture_as_pdf),
                          title: const Text('PDF'),
                          onTap: () => setExportType(ExportType.pdf),
                          trailing: SizedBox(
                            width: 60,
                            child: exportType == ExportType.pdf ? const Icon(Icons.check_outlined) : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        switch (exportType) {
                          case ExportType.pdf:
                            _exportPDF(memory, false);
                            break;
                          case ExportType.markdown:
                            _exportSummaryMarkdown(memory);
                            break;
                          case ExportType.txt:
                            _exportSummaryTxt(memory);
                            break;
                          default:
                            break;
                        }
                      },
                      child: Text('Export', style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ),
                ]
              ],
            ),
          );
        },
      );
    },
  );
}

ListTile _buildListTile(
  BuildContext context, {
  required String title,
  required IconData icon,
  required VoidCallback onTap,
}) =>
    ListTile(title: Text(title), leading: Icon(icon), onTap: onTap);
