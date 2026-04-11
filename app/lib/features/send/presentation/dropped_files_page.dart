import 'package:flutter/material.dart';

import '../../../theme/drift_theme.dart';
import '../application/model.dart';

class DroppedFilesPage extends StatelessWidget {
  const DroppedFilesPage({
    super.key,
    required this.files,
  });

  final List<SendPickedFile> files;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Selected files'),
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: kBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    files.isEmpty
                        ? 'No files were selected.'
                        : '${files.length} file${files.length == 1 ? '' : 's'} ready to preview.',
                    style: driftSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: files.isEmpty
                        ? Center(
                            child: Text(
                              'Drop or select files from the home screen.',
                              textAlign: TextAlign.center,
                              style: driftSans(
                                fontSize: 13,
                                color: kMuted,
                                height: 1.4,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: files.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final file = files[index];
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFA),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFFE5EBEC),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF7F6),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.description_outlined,
                                        size: 18,
                                        color: Color(0xFF4F8B88),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            file.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: driftSans(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: kInk,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            file.path,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: driftSans(
                                              fontSize: 12,
                                              color: kMuted,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
