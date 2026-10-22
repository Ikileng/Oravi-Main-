import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/search/ward_search_engine.dart';
import '../patient_detail_screen.dart';
import '../providers/ward_providers.dart';
import '../theme/clinical_theme.dart';

/// Instant offline search across all beds, patient records, and open loops on the ward.
///
/// Implements PRD Section 7.1 and Tech Arch Section 9 & 14:
/// - Instant offline lookups by bed, name, admission number, alert, or clinical topic.
/// - One-tap navigation directly into patient details.
class WardSearchSheet extends ConsumerStatefulWidget {
  const WardSearchSheet({super.key});

  @override
  ConsumerState<WardSearchSheet> createState() => _WardSearchSheetState();
}

class _WardSearchSheetState extends ConsumerState<WardSearchSheet> {
  final TextEditingController _searchController = TextEditingController();

  final List<String> _quickFilterChips = [
    'STAT',
    'Oxygen',
    'Blood',
    'Allergy',
    'Insulin',
    'Ceftriaxone',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    ref.read(wardSearchQueryProvider.notifier).setQuery(text);
  }

  void _applyChip(String chip) {
    _searchController.text = chip;
    ref.read(wardSearchQueryProvider.notifier).setQuery(chip);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(wardSearchQueryProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(wardSearchResultsProvider);
    final activeQuery = ref.watch(wardSearchQueryProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: ClinicalTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle & Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ClinicalTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.search, color: ClinicalTheme.routineTeal, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'WARD SEARCH',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ClinicalTheme.textPrimary, letterSpacing: 0.5),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: ClinicalTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: ClinicalTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search bed, admission no, patient, drug, or issue...',
                hintStyle: const TextStyle(color: ClinicalTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: ClinicalTheme.routineTeal),
                suffixIcon: activeQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: ClinicalTheme.textMuted),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: ClinicalTheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ClinicalTheme.border),
                ),
              ),
            ),
          ),

          // Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _quickFilterChips.map((chip) {
                final isSelected = activeQuery.toLowerCase() == chip.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(chip, style: const TextStyle(fontSize: 11)),
                    backgroundColor: isSelected ? ClinicalTheme.routineTeal.withValues(alpha: 0.3) : ClinicalTheme.surface,
                    side: BorderSide(
                      color: isSelected ? ClinicalTheme.routineTeal : ClinicalTheme.border,
                      width: 0.8,
                    ),
                    onPressed: () => _applyChip(chip),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, color: ClinicalTheme.border),

          // Search Results List
          Expanded(
            child: activeQuery.isEmpty
                ? const Center(
                    child: Text(
                      'Type a bed number, patient name, admission number, or medical term.',
                      style: TextStyle(color: ClinicalTheme.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  )
                : searchResults.isEmpty
                    ? Center(
                        child: Text(
                          'No matches found on this ward for "$activeQuery".',
                          style: const TextStyle(color: ClinicalTheme.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final result = searchResults[index];
                          return _buildSearchResultRow(context, result);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultRow(BuildContext context, WardSearchResult result) {
    final urgencyColor = result.highestUrgency != null
        ? ClinicalTheme.urgencyColor(result.highestUrgency!)
        : ClinicalTheme.routineTeal;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: urgencyColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: urgencyColor, width: 0.8),
              ),
              child: Text(
                result.patient.bedNumber,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: urgencyColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${result.patient.nameOrInitials} (${result.patient.admissionNumber})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ClinicalTheme.textPrimary),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.arrow_right, size: 16, color: ClinicalTheme.routineTeal),
              Expanded(
                child: Text(
                  result.matchSnippet,
                  style: const TextStyle(fontSize: 12, color: ClinicalTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: ClinicalTheme.textMuted, size: 20),
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PatientDetailScreen(patient: result.patient),
            ),
          );
        },
      ),
    );
  }
}
