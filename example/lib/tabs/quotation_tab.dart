import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import '../pages/quotation_scanner_page.dart';
import '../pages/quotation_realtime_page.dart';
import '../pages/quotation_list_page.dart';

/// Quotation Tab
class QuotationTab extends StatefulWidget {
  const QuotationTab({super.key});

  @override
  State<QuotationTab> createState() => _QuotationTabState();
}

class _QuotationTabState extends State<QuotationTab> {
  // Shared storage for both modes
  final Map<String, ScannedQuotation> _sharedStorage = {};

  @override
  Widget build(BuildContext context) {
    final quotationCount = _sharedStorage.length;
    final totalAmount = _sharedStorage.values
        .where((q) => q.total != null)
        .fold<int>(0, (sum, q) => sum + q.total!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.description,
                  size: 48,
                  color: Colors.purple.shade700,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Quotation Scanner',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Layout Detection + OCR',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (quotationCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMiniStat(Icons.description, '$quotationCount', 'Scanned'),
                        Container(width: 1, height: 24, color: Colors.grey.shade300),
                        _buildMiniStat(Icons.attach_money, '\$$totalAmount', 'Total'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mode 1: Photo (Gallery/Camera)
          _buildModeCard(
            context: context,
            icon: Icons.add_photo_alternate,
            title: 'Photo',
            subtitle: 'Demo quotation images',
            description: 'Select from preset demo images\nto test OCR recognition',
            color: Colors.purple,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuotationScannerPage(
                    sharedStorage: _sharedStorage,
                  ),
                ),
              );
              _sharedStorage.clear();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),

          // Mode 2: Real-time Scan
          _buildModeCard(
            context: context,
            icon: Icons.camera,
            title: 'Real-time Scan',
            subtitle: 'Live camera detection',
            description: 'Point camera at quotation\nfor instant recognition',
            color: Colors.deepPurple,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuotationRealtimePage(
                    sharedStorage: _sharedStorage,
                  ),
                ),
              );
              _sharedStorage.clear();
              setState(() {});
            },
          ),
          const SizedBox(height: 16),

          // View Results button (if has data)
          if (quotationCount > 0) ...[
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => QuotationListPage(
                      quotations: _sharedStorage.values.toList(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.list),
              label: Text('View All Results ($quotationCount)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear All'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Info section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Features',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildFeatureItem('Layout Detection finds Table regions'),
                _buildFeatureItem('OCR extracts text from tables'),
                _buildFeatureItem('Auto-extract items, prices, totals'),
                _buildFeatureItem('Deduplicate by quotation number'),
              ],
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
                    'This is a specialized demo for specific quotation format, not a general-purpose solution.',
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

  Widget _buildMiniStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.purple),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '  -  ',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: Text('Delete all ${_sharedStorage.length} scanned quotations?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _sharedStorage.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
