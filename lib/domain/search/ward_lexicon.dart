/// Ward lexicon mapping clinical topics, abbreviations, English, and Kiswahili
/// terms commonly used across Kenyan hospital inpatient wards.
///
/// Implements PRD Section 8A (FR-41 & FR-192):
/// "A ward lexicon. Build a vocabulary of terms, abbreviations, and local usage
/// from real ward language: urine, UO, passing urine, mkojo; SpO2, sats, oxygen;
/// and so on, across English, Kiswahili, and mixed speech."
class WardLexicon {
  /// Core synonym dictionary indexed by canonical clinical topic key.
  static final Map<String, List<String>> topicSynonyms = {
    'urine': [
      'urine',
      'uo',
      'passing urine',
      'mkojo',
      'catheter',
      'foley',
      'anuria',
      'oliguria',
      'polyuria',
      'diuresis',
      'bag emptied',
      'fluid balance',
      'output',
    ],
    'oxygen': [
      'spo2',
      'sats',
      'oxygen',
      'o2',
      'desat',
      'desaturating',
      'hypoxia',
      'hewa ya oksijeni',
      'prongs',
      'nasal prongs',
      'nasal cannula',
      'mask',
      'room air',
      '2l',
      '4l',
      'litres',
      'liters',
    ],
    'blood': [
      'blood',
      'cross-match',
      'crossmatch',
      'group and match',
      'transfusion',
      'prbc',
      'units',
      'hb',
      'haemoglobin',
      'hemoglobin',
      'damu',
      'bleeding',
      'drain output',
    ],
    'blood_pressure': [
      'bp',
      'blood pressure',
      'presha',
      'hypotension',
      'hypertension',
      'systolic',
      'diastolic',
      'map',
      'shock',
    ],
    'allergy': [
      'allergy',
      'allergic',
      'allergies',
      'reaction',
      'mzio',
      'anaphylaxis',
      'rash',
      'penicillin',
    ],
    'pain': [
      'pain',
      'ache',
      'uchungu',
      'maumivu',
      'analgesia',
      'paracetamol',
      'morphine',
      'tramadol',
      'diclofenac',
      'tender',
      'tenderness',
    ],
    'temperature': [
      'fever',
      'temp',
      'temperature',
      'joto',
      'febrile',
      'pyrexia',
      'rigors',
      'chills',
      'hot',
    ],
    'glucose': [
      'glucose',
      'sugar',
      'rbs',
      'fbs',
      'dextrose',
      'insulin',
      'sliding scale',
      'sukari',
      'dka',
      'ketoacidosis',
    ],
    'antibiotics': [
      'antibiotic',
      'antibiotics',
      'ceftriaxone',
      'gentamicin',
      'metronidazole',
      'amoxicillin',
      'augmentin',
      'crystalline',
      'dawa',
      'iv antibiotics',
    ],
    'fluid_balance': [
      'fluids',
      'fluid',
      'ivf',
      'drip',
      'saline',
      'normal saline',
      'hartmann',
      'dextrose',
      'input',
      'intake',
      'output',
    ],
  };

  /// Diagnostic boundary trigger phrases (PRD Section 8A FR-40 & Example 8).
  ///
  /// Questions asking for clinical diagnosis, prognosis, or prediction are refused
  /// while returning relevant objective records and offering a direct button to the doctor.
  static final List<String> diagnosticTriggers = [
    'going into',
    'kidney failure',
    'renal failure',
    'heart failure',
    'sepsis',
    'septic',
    'dying',
    'will he survive',
    'will she survive',
    'diagnose',
    'diagnosis',
    'prognosis',
    'prescribe',
    'what medicine should i give',
    'what should i prescribe',
    'cause of death',
  ];

  /// Checks if a query string contains diagnostic or predictive intent.
  static bool isDiagnosticOrPredictiveQuery(String query) {
    final lower = query.toLowerCase().trim();
    for (final trigger in diagnosticTriggers) {
      if (lower.contains(trigger)) {
        return true;
      }
    }
    return false;
  }

  /// Expands a clinician query into all matching search terms across topics and synonyms.
  static Set<String> expandSearchTerms(String query) {
    final lower = query.toLowerCase().trim();
    final terms = <String>{};

    // 1. Add individual meaningful words from the query (excluding stop words)
    final words = lower
        .split(RegExp(r'[^a-zA-Z0-9_\-]+'))
        .where((w) => w.length >= 2 && !_stopWords.contains(w));
    terms.addAll(words);

    // 2. Scan known topics for match or partial match
    for (final entry in topicSynonyms.entries) {
      final topicKey = entry.key;
      final synonyms = entry.value;

      final matchesTopic = synonyms.any((syn) => lower.contains(syn)) ||
          lower.contains(topicKey.replaceAll('_', ' '));

      if (matchesTopic) {
        // Add all synonyms for this clinical concept to ensure full recall
        terms.addAll(synonyms);
      }
    }

    return terms;
  }

  /// Canonical stop words in English and Kiswahili to ignore in tokenization.
  static const Set<String> _stopWords = {
    'a',
    'an',
    'the',
    'in',
    'on',
    'at',
    'to',
    'for',
    'of',
    'and',
    'or',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'has',
    'have',
    'had',
    'how',
    'what',
    'when',
    'where',
    'who',
    'did',
    'any',
    'does',
    'his',
    'her',
    'their',
    'this',
    'that',
    'about',
    'tell',
    'me',
    'know',
    'last',
    'hours',
    'hour',
    'recent',
    'happened',
    'updates',
    'summary',
    'should',
    'i',
    'we',
    'shift',
    'masaa',
    'leo',
    'hivi',
    'ya',
    'wa',
    'kwa',
    'na',
    'katika',
    'ni',
    'je',
    'wake',
    'yake',
    'yaliyopita',
  };
}
