import 'package:flutter/material.dart';

import 'tabs/ocr_tab.dart';
import 'tabs/kie_tab.dart';
import 'tabs/invoice_tab.dart';
import 'tabs/quotation_tab.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Kit Demo'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.text_fields), text: 'OCR'),
            Tab(icon: Icon(Icons.document_scanner), text: 'KIE'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Invoice'),
            Tab(icon: Icon(Icons.description), text: 'Quotation'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          OcrTab(searchController: _searchController),
          const KieTab(),
          const InvoiceTab(),
          const QuotationTab(),
        ],
      ),
    );
  }
}
