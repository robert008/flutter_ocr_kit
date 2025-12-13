import 'package:flutter/material.dart';

import '../invoice_scanner_page.dart';

/// Invoice Tab
class InvoiceTab extends StatelessWidget {
  const InvoiceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Invoice Scanner Card
          Card(
            color: Colors.deepOrange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        color: Colors.deepOrange.shade700,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Invoice Scanner',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Real-time Taiwan e-invoice scanning:\n'
                    '- Extracts invoice number (XX-XXXXXXXX)\n'
                    '- Extracts amount & period\n'
                    '- Auto-deduplication by invoice number',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const InvoiceScannerPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Start Scanning'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This is a specialized demo for Taiwan e-invoice format, not a general-purpose solution.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
