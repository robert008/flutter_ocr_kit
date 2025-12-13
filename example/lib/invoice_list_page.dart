import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

/// Invoice List Page
///
/// Displays scanned invoices grouped by period (month)
class InvoiceListPage extends StatelessWidget {
  final List<ScannedInvoice> invoices;

  const InvoiceListPage({super.key, required this.invoices});

  @override
  Widget build(BuildContext context) {
    // Group invoices by period
    final grouped = <String, List<ScannedInvoice>>{};
    for (final invoice in invoices) {
      final key = invoice.groupKey;
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(invoice);
    }

    // Sort groups by period (newest first)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // Calculate totals
    final totalAmount = invoices
        .where((i) => i.amount != null)
        .fold<int>(0, (sum, i) => sum + i.amount!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanned Invoices'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Summary header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.deepOrange.shade200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  icon: Icons.receipt_long,
                  label: 'Total Invoices',
                  value: '${invoices.length}',
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.deepOrange.shade200,
                ),
                _buildSummaryItem(
                  icon: Icons.attach_money,
                  label: 'Total Amount',
                  value: '\$$totalAmount',
                ),
              ],
            ),
          ),

          // Invoice list
          Expanded(
            child: invoices.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No invoices scanned yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: sortedKeys.length,
                    itemBuilder: (context, index) {
                      final period = sortedKeys[index];
                      final periodInvoices = grouped[period]!;
                      final periodTotal = periodInvoices
                          .where((i) => i.amount != null)
                          .fold<int>(0, (sum, i) => sum + i.amount!);

                      return _buildPeriodSection(
                        context,
                        period: period,
                        invoices: periodInvoices,
                        periodTotal: periodTotal,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.deepOrange),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.deepOrange,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSection(
    BuildContext context, {
    required String period,
    required List<ScannedInvoice> invoices,
    required int periodTotal,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.calendar_month, size: 18, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Text(
                period,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                '${invoices.length} invoices',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '\$$periodTotal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Invoice items
        ...invoices.map((invoice) => _buildInvoiceItem(context, invoice)),
      ],
    );
  }

  Widget _buildInvoiceItem(BuildContext context, ScannedInvoice invoice) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.receipt,
            color: Colors.deepOrange,
          ),
        ),
        title: Text(
          invoice.invoiceNumber,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (invoice.storeName != null)
              Text(
                invoice.storeName!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              _formatDateTime(invoice.scannedAt),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        trailing: Text(
          invoice.displayAmount,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: invoice.amount != null ? Colors.green.shade700 : Colors.grey,
          ),
        ),
        onTap: () => _showInvoiceDetail(context, invoice),
      ),
    );
  }

  void _showInvoiceDetail(BuildContext context, ScannedInvoice invoice) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long, color: Colors.deepOrange, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.invoiceNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (invoice.period != null)
                        Text(
                          invoice.period!,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Details
            _buildDetailRow('Store', invoice.storeName ?? '-'),
            _buildDetailRow('Amount', invoice.displayAmount),
            _buildDetailRow('Period', invoice.period ?? '-'),
            _buildDetailRow('Scanned', _formatDateTime(invoice.scannedAt)),

            const SizedBox(height: 24),

            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Close'),
              ),
            ),

            // Safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
