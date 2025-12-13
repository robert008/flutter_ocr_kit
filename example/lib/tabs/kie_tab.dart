import 'package:flutter/material.dart';

import 'package:flutter_ocr_kit/flutter_ocr_kit.dart';

import '../pages/camera_kie_page.dart';
import '../pages/image_kie_page.dart';

/// KIE Tab - Key Information Extraction (Simple KIE only)
class KieTab extends StatefulWidget {
  const KieTab({super.key});

  @override
  State<KieTab> createState() => _KieTabState();
}

class _KieTabState extends State<KieTab> {
  // SimpleKIE: entity type toggles
  final Map<EntityType, bool> _enabledEntityTypes = {
    for (final type in EntityType.values) type: true,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildSimpleKieCard()],
      ),
    );
  }

  Widget _buildSimpleKieCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.text_fields, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'SimpleKIE - Regex Patterns',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Extract entities using pattern matching',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),

            const Divider(height: 24),

            // Entity type toggles
            const Text(
              'Entity Types:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: EntityType.values.map((type) {
                final isEnabled = _enabledEntityTypes[type] ?? false;
                return FilterChip(
                  label: Text(type.label),
                  selected: isEnabled,
                  onSelected: (selected) {
                    setState(() => _enabledEntityTypes[type] = selected);
                  },
                  selectedColor: type.color.withOpacity(0.3),
                  checkmarkColor: type.color,
                  side: BorderSide(
                    color: isEnabled ? type.color : Colors.grey.shade400,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final type in EntityType.values) {
                        _enabledEntityTypes[type] = true;
                      }
                    });
                  },
                  icon: const Icon(Icons.select_all, size: 16),
                  label: const Text('All'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final type in EntityType.values) {
                        _enabledEntityTypes[type] = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.deselect, size: 16),
                  label: const Text('None'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _getEnabledTypes().isNotEmpty
                        ? () => _navigateToSimpleKieCamera(context)
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _getEnabledTypes().isNotEmpty
                        ? () => _navigateToSimpleKieImage(context)
                        : null,
                    icon: const Icon(Icons.image),
                    label: const Text('Image'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<EntityType> _getEnabledTypes() {
    return _enabledEntityTypes.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
  }

  void _navigateToSimpleKieCamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraKiePage(enabledTypes: _getEnabledTypes()),
      ),
    );
  }

  void _navigateToSimpleKieImage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageKiePage(enabledTypes: _getEnabledTypes()),
      ),
    );
  }
}
