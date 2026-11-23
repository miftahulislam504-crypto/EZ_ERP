import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/adaptive_dialog.dart';

/// Posts a sales invoice. If the customer would go over their credit limit the
/// server refuses; the poster is then asked to confirm, and the override is
/// recorded on the invoice. Returns true when the invoice was posted and false
/// when the poster chose not to override. Other errors are thrown.
Future<bool> postSalesInvoice(BuildContext context, WidgetRef ref, String id) async {
  final client = ref.read(supabaseProvider);
  try {
    await client.rpc('post_sales_invoice', params: {'p_id': id, 'p_override_credit': false});
    return true;
  } catch (e) {
    final message = friendlyError(e);
    if (!message.startsWith('Credit limit exceeded')) rethrow;
    if (!context.mounted) return false;
    final go = await confirmDialog(
      context,
      title: 'Over the credit limit',
      message: '$message\n\nPost it anyway? The override is recorded on the invoice.',
      confirmLabel: 'Post anyway',
      danger: true,
    );
    if (!go) return false;
    await client.rpc('post_sales_invoice', params: {'p_id': id, 'p_override_credit': true});
    return true;
  }
}
