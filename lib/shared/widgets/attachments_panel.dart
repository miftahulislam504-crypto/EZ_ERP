import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'feedback.dart';

typedef _AttKey = ({String type, String id});

final _attachmentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, _AttKey>((ref, key) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('attachments')
      .select('id, file_name, storage_path, mime_type, size_bytes, uploaded_by, created_at')
      .eq('org_id', orgId)
      .eq('entity_type', key.type)
      .eq('entity_id', key.id)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows);
});

const _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'pdf': 'application/pdf',
};

String _size(num? bytes) {
  if (bytes == null) return '';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// Files attached to a record: bills, receipts and supporting documents.
/// On phones a bill can be photographed directly.
class AttachmentsPanel extends ConsumerStatefulWidget {
  const AttachmentsPanel({super.key, required this.entityType, required this.entityId, this.canUpload = true});

  final String entityType;
  final String entityId;
  final bool canUpload;

  @override
  ConsumerState<AttachmentsPanel> createState() => _AttachmentsPanelState();
}

class _AttachmentsPanelState extends ConsumerState<AttachmentsPanel> {
  bool _busy = false;

  bool get _cameraAvailable => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  _AttKey get _key => (type: widget.entityType, id: widget.entityId);

  Future<void> _add() async {
    var source = 'file';
    if (_cameraAvailable) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
              ListTile(leading: const Icon(Icons.attach_file_rounded), title: const Text('Choose a file'), onTap: () => Navigator.pop(ctx, 'file')),
            ],
          ),
        ),
      );
      if (choice == null) return;
      source = choice;
    }

    Uint8List? bytes;
    String name;
    if (source == 'camera') {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, imageQuality: 85);
      if (shot == null) return;
      bytes = await shot.readAsBytes();
      name = shot.name;
    } else {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      );
      if (picked == null || picked.files.isEmpty) return;
      bytes = picked.files.first.bytes;
      name = picked.files.first.name;
    }
    if (bytes == null) {
      if (mounted) showToast(context, 'Could not read that file.', error: true);
      return;
    }
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) showToast(context, 'Choose a file smaller than 10 MB.', error: true);
      return;
    }

    final m = ref.read(activeMembershipProvider);
    final uid = ref.read(currentUserIdProvider);
    if (m == null || uid == null) return;
    setState(() => _busy = true);
    try {
      final client = ref.read(supabaseProvider);
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${m.orgId}/${widget.entityType}/${widget.entityId}/${DateTime.now().millisecondsSinceEpoch}_$safe';
      final mime = _mimeByExt[ext];
      await client.storage.from('attachments').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
      await client.from('attachments').insert({
        'org_id': m.orgId,
        'entity_type': widget.entityType,
        'entity_id': widget.entityId,
        'file_name': name,
        'storage_path': path,
        'mime_type': mime,
        'size_bytes': bytes.length,
        'uploaded_by': uid,
      });
      ref.invalidate(_attachmentsProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> a) async {
    try {
      final url = await ref.read(supabaseProvider).storage.from('attachments').createSignedUrl('${a['storage_path']}', 3600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showToast(context, 'Could not open the file.', error: true);
    }
  }

  Future<void> _remove(Map<String, dynamic> a) async {
    try {
      final client = ref.read(supabaseProvider);
      await client.from('attachments').delete().eq('id', a['id'] as Object);
      try {
        await client.storage.from('attachments').remove(['${a['storage_path']}']);
      } catch (_) {
        // The record is gone; a leftover file is cleaned up later.
      }
      ref.invalidate(_attachmentsProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_attachmentsProvider(_key));
    final me = ref.watch(currentUserIdProvider);
    return AppCard(
      padding: const EdgeInsets.all(18),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Attachments', style: AppText.h3)),
              if (widget.canUpload)
                AppButton(
                  label: _cameraAvailable ? 'Add photo or file' : 'Add file',
                  icon: _cameraAvailable ? Icons.photo_camera_outlined : Icons.upload_rounded,
                  kind: AppButtonKind.secondary,
                  compact: true,
                  loading: _busy,
                  onPressed: _add,
                ),
            ],
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 2)),
            error: (e, _) => Text(friendlyError(e), style: AppText.small),
            data: (rows) {
              if (rows.isEmpty) return Text('No files attached yet. Add the bill, receipt or any supporting document.', style: AppText.small);
              return Column(
                children: [
                  for (final a in rows)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        '${a['mime_type']}'.startsWith('image') ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: Text('${a['file_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
                      subtitle: Text('${_size(a['size_bytes'] as num?)}  ${Fmt.timeAgo(Fmt.parse(a['created_at'] as String?))}', style: AppText.small),
                      onTap: () => _open(a),
                      trailing: widget.canUpload && a['uploaded_by'] == me
                          ? IconButton(
                              tooltip: 'Remove',
                              onPressed: () => _remove(a),
                              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.textMuted),
                            )
                          : null,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
