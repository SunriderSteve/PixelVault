import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/learn_videography_model.dart';

class LearnVideographyListPage extends StatefulWidget {
  const LearnVideographyListPage({super.key});
  @override
  _LearnVideographyListPageState createState() =>
      _LearnVideographyListPageState();
}

class _LearnVideographyListPageState extends State<LearnVideographyListPage> {
  final _searchCtrl = TextEditingController();
  late final List<VideographyGuide> _all;
  late List<VideographyGuide> _filtered;

  @override
  void initState() {
    super.initState();
    _all = DataRepository().getAllVideographyGuides();
    _filtered = List.from(_all);
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(_all)
          : _all.where((g) => g.name.toLowerCase().contains(q)).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    const tileMax = 420.0;
    final cols = math.max(2, (MediaQuery.of(c).size.width / tileMax).floor());
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: const Text(
          'Videography Guides',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // search bar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search Videography Guides',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchCtrl.clear(),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            // grid
            Expanded(
              child: GridView.builder(
                itemCount: _filtered.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3 / 2,
                ),
                itemBuilder: (_, i) {
                  final guide = _filtered[i];
                  // use first cover if present
                  final img = guide.coverImages.isNotEmpty
                      ? guide.coverImages.first
                      : '';
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () =>
                          context.push('/learn/videography-guides/${guide.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: img.isNotEmpty
                                ? AvifImage.asset(img, fit: BoxFit.cover)
                                : const SizedBox.shrink(),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              guide.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontVariations: [FontVariation('wght', 500)],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
