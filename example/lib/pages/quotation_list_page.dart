import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

/// Quotation List Page
///
/// Displays scanned quotations with summary statistics
class QuotationListPage extends StatelessWidget {
  final List<ScannedQuotation> quotations;

  const QuotationListPage({super.key, required this.quotations});

  @override
  Widget build(BuildContext context) {
    // Calculate totals
    final totalAmount = quotations
        .where((q) => q.total != null)
        .fold<int>(0, (sum, q) => sum + q.total!);

    final totalItems = quotations.fold<int>(0, (sum, q) => sum + q.items.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanned Quotations'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Summary header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.purple.shade200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  icon: Icons.description,
                  label: 'Quotations',
                  value: '${quotations.length}',
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.purple.shade200,
                ),
                _buildSummaryItem(
                  icon: Icons.inventory_2,
                  label: 'Total Items',
                  value: '$totalItems',
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.purple.shade200,
                ),
                _buildSummaryItem(
                  icon: Icons.attach_money,
                  label: 'Total Amount',
                  value: '\$$totalAmount',
                ),
              ],
            ),
          ),

          // Quotation list
          Expanded(
            child: quotations.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No quotations scanned yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: quotations.length,
                    itemBuilder: (context, index) {
                      final quotation = quotations[index];
                      return _buildQuotationItem(context, quotation);
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
        Icon(icon, size: 24, color: Colors.purple),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildQuotationItem(BuildContext context, ScannedQuotation quotation) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.description,
            color: Colors.purple,
          ),
        ),
        title: Text(
          quotation.quotationNumber,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quotation.customerName != null)
              Text(
                quotation.customerName!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Row(
              children: [
                Text(
                  quotation.quotationDate ?? '-',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                const Spacer(),
                Text(
                  quotation.displayTotal,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: quotation.total != null
                        ? Colors.green.shade700
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        children: [
          // Items list
          if (quotation.items.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  const Expanded(flex: 4, child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  const Expanded(flex: 2, child: Text('Price', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                  const Expanded(flex: 2, child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                ],
              ),
            ),
            ...quotation.items.map((item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '\$${item.unitPrice}',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '\$${item.amount}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            )),
          ],

          // Totals
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple.shade50,
            child: Column(
              children: [
                if (quotation.subtotal != null)
                  _buildTotalRow('Subtotal', '\$${quotation.subtotal}'),
                if (quotation.tax != null)
                  _buildTotalRow('Tax (5%)', '\$${quotation.tax}'),
                if (quotation.total != null)
                  _buildTotalRow('Total', '\$${quotation.total}', isBold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isBold ? 16 : 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? Colors.purple : Colors.black,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
