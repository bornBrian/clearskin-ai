import '../../data/models/profile.dart';

/// Functional families an ingredient can belong to. Conflict rules and
/// routine matching operate on families, not individual names.
enum Family {
  retinoid,
  prescriptionRetinoid,
  aha,
  bha,
  pha,
  vitaminC, // pure L-ascorbic acid: potent, low pH, unstable
  vitaminCDerivative,
  benzoylPeroxide,
  niacinamide,
  azelaicAcid,
  brightener,
  hydroquinone,
  sulfur,
  physicalExfoliant,
  humectant,
  emollient,
  occlusive,
  barrier,
  soothing,
  antioxidant,
  peptide,
  sunscreenMineral,
  sunscreenChemical,
  fragrance,
  essentialOil,
  dryingAlcohol,
  harshSurfactant,
  allergenPreservative,
  preservative,
  caffeine,
}

/// Families that make a product an "active" that needs care when combining.
const exfoliatingFamilies = {
  Family.aha,
  Family.bha,
  Family.pha,
  Family.physicalExfoliant,
};

const sunscreenFamilies = {Family.sunscreenMineral, Family.sunscreenChemical};

class Ingredient {
  const Ingredient(
    this.id,
    this.name,
    this.aliases,
    this.families,
    this.summary, {
    this.comedogenic = 0,
    this.irritancy = 0,
    this.pregnancyCaution = PregnancyCaution.none,
    this.fungalAcneTrigger = false,
    this.goodFor = const {},
  });

  final String id;
  final String name;

  /// Lower-case INCI names and common names used for matching.
  final List<String> aliases;
  final Set<Family> families;

  /// One plain-language sentence a non-expert understands.
  final String summary;

  /// 0-5 (Fulton scale). Pore-clogging potential varies by formula and
  /// person; we only surface >= 3 to acne-prone users.
  final int comedogenic;

  /// 0 gentle .. 3 frequently irritating.
  final int irritancy;
  final PregnancyCaution pregnancyCaution;

  /// May feed Malassezia (fungal acne): fatty acids C12-C18, their esters,
  /// polysorbates and most plant oils.
  final bool fungalAcneTrigger;
  final Set<Concern> goodFor;
}

enum PregnancyCaution {
  none,

  /// Generally fine but worth confirming with a clinician (e.g. leave-on
  /// salicylic acid above wash-off levels).
  askDoctor,

  /// Commonly advised to avoid during pregnancy / breastfeeding.
  avoid,
}

/// Curated, evidence-informed ingredient knowledge. Kept as code (not a
/// downloaded file) so it is reviewed, versioned and unit-tested.
abstract final class IngredientKb {
  static final List<Ingredient> all = [
    // ── Retinoids ───────────────────────────────────────────────────────
    const Ingredient(
      'retinol',
      'Retinol',
      ['retinol'],
      {Family.retinoid, Family.antioxidant},
      'Vitamin A that speeds cell turnover: smooths lines, texture, marks and clogged pores. Start 2–3 nights a week.',
      irritancy: 2,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {
        Concern.fineLines,
        Concern.texture,
        Concern.darkSpots,
        Concern.acne,
        Concern.blackheads,
      },
    ),
    const Ingredient(
      'retinal',
      'Retinal (retinaldehyde)',
      ['retinal', 'retinaldehyde'],
      {Family.retinoid},
      'A faster-acting form of vitamin A, one step closer to the active form than retinol.',
      irritancy: 2,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {Concern.fineLines, Concern.texture, Concern.acne},
    ),
    const Ingredient(
      'hpr',
      'Hydroxypinacolone retinoate',
      ['hydroxypinacolone retinoate', 'granactive retinoid'],
      {Family.retinoid},
      'A gentler retinoid ester that tends to irritate less than retinol.',
      irritancy: 1,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {Concern.fineLines, Concern.texture},
    ),
    const Ingredient(
      'retinyl_palmitate',
      'Retinyl palmitate',
      ['retinyl palmitate', 'retinyl acetate', 'retinyl propionate'],
      {Family.retinoid},
      'A mild vitamin A ester; much weaker than retinol but still a retinoid.',
      irritancy: 1,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {Concern.fineLines},
    ),
    const Ingredient(
      'adapalene',
      'Adapalene',
      ['adapalene'],
      {Family.retinoid},
      'A stable retinoid proven for acne and clogged pores (0.1% is over-the-counter in many countries).',
      irritancy: 2,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {Concern.acne, Concern.blackheads, Concern.texture},
    ),
    const Ingredient(
      'tretinoin',
      'Tretinoin',
      ['tretinoin', 'retinoic acid'],
      {Family.retinoid, Family.prescriptionRetinoid},
      'Prescription-strength vitamin A. Highly effective; use only as directed by your prescriber.',
      irritancy: 3,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {
        Concern.acne,
        Concern.fineLines,
        Concern.darkSpots,
        Concern.texture,
      },
    ),
    const Ingredient(
      'tazarotene',
      'Tazarotene',
      ['tazarotene'],
      {Family.retinoid, Family.prescriptionRetinoid},
      'A strong prescription retinoid. Must not be used during pregnancy.',
      irritancy: 3,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {Concern.acne, Concern.fineLines},
    ),
    const Ingredient(
      'bakuchiol',
      'Bakuchiol',
      ['bakuchiol'],
      {Family.antioxidant, Family.soothing},
      'A plant-derived retinol alternative with early evidence and less irritation. Not a retinoid.',
      goodFor: {Concern.fineLines, Concern.sensitivity},
    ),

    // ── Exfoliating acids ──────────────────────────────────────────────
    const Ingredient(
      'glycolic',
      'Glycolic acid',
      ['glycolic acid'],
      {Family.aha},
      'The smallest AHA: dissolves dull surface cells for smoother, brighter skin. Raises sun sensitivity.',
      irritancy: 2,
      goodFor: {
        Concern.texture,
        Concern.darkSpots,
        Concern.unevenTone,
        Concern.razorBumps,
      },
    ),
    const Ingredient(
      'lactic',
      'Lactic acid',
      ['lactic acid'],
      {Family.aha, Family.humectant},
      'A gentler, hydrating AHA that smooths and brightens.',
      irritancy: 1,
      goodFor: {Concern.texture, Concern.dryness, Concern.unevenTone},
    ),
    const Ingredient(
      'mandelic',
      'Mandelic acid',
      ['mandelic acid'],
      {Family.aha},
      'A large, slow-penetrating AHA: one of the gentlest options for sensitive and deeper skin tones.',
      irritancy: 1,
      goodFor: {Concern.texture, Concern.acne, Concern.darkSpots},
    ),
    const Ingredient(
      'malic',
      'Malic acid',
      ['malic acid'],
      {Family.aha},
      'A fruit AHA, usually a supporting exfoliant.',
      irritancy: 1,
    ),
    const Ingredient(
      'tartaric',
      'Tartaric acid',
      ['tartaric acid'],
      {Family.aha},
      'A fruit AHA, usually a supporting exfoliant.',
      irritancy: 1,
    ),
    const Ingredient(
      'salicylic',
      'Salicylic acid (BHA)',
      ['salicylic acid', 'bha', 'beta hydroxy acid'],
      {Family.bha},
      'Oil-soluble exfoliant that clears inside pores: the go-to for blackheads, breakouts and razor bumps.',
      irritancy: 1,
      pregnancyCaution: PregnancyCaution.askDoctor,
      goodFor: {
        Concern.acne,
        Concern.blackheads,
        Concern.oiliness,
        Concern.largePores,
        Concern.razorBumps,
      },
    ),
    const Ingredient(
      'betaine_salicylate',
      'Betaine salicylate',
      ['betaine salicylate'],
      {Family.bha},
      'A milder salicylic acid relative.',
      goodFor: {Concern.blackheads, Concern.acne},
    ),
    const Ingredient(
      'willow_bark',
      'Willow bark extract',
      [
        'salix alba bark extract',
        'salix nigra bark extract',
        'willow bark extract',
      ],
      {Family.soothing},
      'Contains salicin, which is NOT the same as salicylic acid; mostly soothing, minimal exfoliation.',
    ),
    const Ingredient(
      'gluconolactone',
      'Gluconolactone (PHA)',
      ['gluconolactone', 'lactobionic acid', 'galactose'],
      {Family.pha, Family.humectant},
      'A very gentle exfoliating acid that also hydrates. Good for sensitive skin.',
      goodFor: {Concern.texture, Concern.sensitivity},
    ),
    const Ingredient(
      'urea',
      'Urea',
      ['urea'],
      {Family.humectant},
      'Deeply hydrating; at higher strengths it also softens rough, flaky skin.',
      goodFor: {Concern.dryness, Concern.texture},
    ),

    // ── Acne fighters ──────────────────────────────────────────────────
    const Ingredient(
      'bpo',
      'Benzoyl peroxide',
      ['benzoyl peroxide'],
      {Family.benzoylPeroxide},
      'Kills acne bacteria; resistance does not develop. Can dry skin and bleach fabrics.',
      irritancy: 2,
      goodFor: {Concern.acne},
    ),
    const Ingredient(
      'sulfur',
      'Sulfur',
      ['sulfur', 'sulphur'],
      {Family.sulfur},
      'Gently drying and antimicrobial; useful as a spot treatment.',
      irritancy: 1,
      goodFor: {Concern.acne},
    ),
    const Ingredient(
      'azelaic',
      'Azelaic acid',
      ['azelaic acid', 'potassium azeloyl diglycinate'],
      {Family.azelaicAcid, Family.brightener},
      'Multitasker for breakouts, redness and dark marks; gentle enough for many sensitive skins and pregnancy-friendly.',
      irritancy: 1,
      goodFor: {
        Concern.acne,
        Concern.redness,
        Concern.darkSpots,
        Concern.unevenTone,
      },
    ),
    const Ingredient(
      'zinc_pca',
      'Zinc PCA',
      ['zinc pca', 'zinc gluconate'],
      {Family.soothing},
      'Helps regulate oil and calm blemishes.',
      goodFor: {Concern.oiliness, Concern.acne},
    ),
    const Ingredient(
      'tea_tree',
      'Tea tree oil',
      [
        'melaleuca alternifolia leaf oil',
        'tea tree oil',
        'melaleuca alternifolia (tea tree) leaf oil',
      ],
      {Family.essentialOil},
      'Mild evidence for blemishes but a common allergen, especially when oxidised.',
      irritancy: 2,
      goodFor: {Concern.acne},
    ),

    // ── Vitamin C & brighteners ────────────────────────────────────────
    const Ingredient(
      'laa',
      'Vitamin C (L-ascorbic acid)',
      ['ascorbic acid', 'l-ascorbic acid'],
      {Family.vitaminC, Family.antioxidant, Family.brightener},
      'The most studied form of vitamin C: brightens, fades marks and boosts sunscreen protection. Can sting.',
      irritancy: 2,
      goodFor: {Concern.darkSpots, Concern.unevenTone, Concern.fineLines},
    ),
    const Ingredient(
      'vitc_deriv',
      'Vitamin C derivative',
      [
        'sodium ascorbyl phosphate',
        'magnesium ascorbyl phosphate',
        'ascorbyl glucoside',
        '3-o-ethyl ascorbic acid',
        'ethyl ascorbic acid',
        'tetrahexyldecyl ascorbate',
        'ascorbyl tetraisopalmitate',
        'ascorbyl palmitate',
      ],
      {Family.vitaminCDerivative, Family.antioxidant, Family.brightener},
      'A gentler, more stable form of vitamin C.',
      goodFor: {Concern.darkSpots, Concern.unevenTone},
    ),
    const Ingredient(
      'niacinamide',
      'Niacinamide',
      ['niacinamide', 'nicotinamide'],
      {Family.niacinamide, Family.barrier, Family.brightener},
      'Vitamin B3: strengthens the barrier, balances oil, softens redness and marks. Plays well with almost everything.',
      goodFor: {
        Concern.oiliness,
        Concern.largePores,
        Concern.redness,
        Concern.darkSpots,
        Concern.acne,
        Concern.sensitivity,
      },
    ),
    const Ingredient(
      'tranexamic',
      'Tranexamic acid',
      ['tranexamic acid'],
      {Family.brightener},
      'Targets stubborn dark marks and melasma with low irritation.',
      goodFor: {Concern.darkSpots, Concern.unevenTone},
    ),
    const Ingredient(
      'arbutin',
      'Alpha-arbutin',
      ['alpha-arbutin', 'arbutin', 'beta-arbutin'],
      {Family.brightener},
      'Fades dark spots by calming pigment production.',
      goodFor: {Concern.darkSpots, Concern.unevenTone},
    ),
    const Ingredient(
      'kojic',
      'Kojic acid',
      ['kojic acid', 'kojic dipalmitate'],
      {Family.brightener},
      'A brightening agent for dark marks; can occasionally irritate.',
      irritancy: 1,
      goodFor: {Concern.darkSpots},
    ),
    const Ingredient(
      'licorice',
      'Licorice root extract',
      [
        'glycyrrhiza glabra root extract',
        'glycyrrhiza glabra (licorice) root extract',
        'dipotassium glycyrrhizate',
      ],
      {Family.brightener, Family.soothing},
      'Calms redness and helps even tone.',
      goodFor: {Concern.redness, Concern.darkSpots},
    ),
    const Ingredient(
      'hydroquinone',
      'Hydroquinone',
      ['hydroquinone'],
      {Family.hydroquinone, Family.brightener},
      'Strong pigment inhibitor. Use short-term under medical guidance; restricted in many countries.',
      irritancy: 2,
      pregnancyCaution: PregnancyCaution.avoid,
      goodFor: {Concern.darkSpots},
    ),

    // ── Hydration & barrier ────────────────────────────────────────────
    const Ingredient(
      'glycerin',
      'Glycerin',
      ['glycerin', 'glycerine', 'glycerol'],
      {Family.humectant},
      'One of the best-proven hydrators: pulls water into the skin.',
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'ha',
      'Hyaluronic acid',
      [
        'hyaluronic acid',
        'sodium hyaluronate',
        'hydrolyzed hyaluronic acid',
        'sodium acetylated hyaluronate',
        'sodium hyaluronate crosspolymer',
      ],
      {Family.humectant},
      'Binds water for plump, hydrated skin. Apply to damp skin and seal with moisturizer.',
      goodFor: {Concern.dryness, Concern.fineLines},
    ),
    const Ingredient(
      'ceramides',
      'Ceramides',
      [
        'ceramide np',
        'ceramide ap',
        'ceramide eop',
        'ceramide ns',
        'ceramide eos',
        'ceramide 3',
        'ceramide 6 ii',
        'ceramide 1',
        'ceramide ng',
      ],
      {Family.barrier, Family.emollient},
      'Skin-identical lipids that repair a damaged, irritated barrier.',
      goodFor: {Concern.dryness, Concern.sensitivity, Concern.redness},
    ),
    const Ingredient(
      'cholesterol',
      'Cholesterol',
      ['cholesterol'],
      {Family.barrier, Family.emollient},
      'Barrier lipid that works with ceramides.',
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'phytosphingosine',
      'Phytosphingosine',
      ['phytosphingosine'],
      {Family.barrier, Family.soothing},
      'Barrier-supporting lipid with calming properties.',
    ),
    const Ingredient(
      'panthenol',
      'Panthenol (vitamin B5)',
      ['panthenol', 'd-panthenol', 'dexpanthenol'],
      {Family.humectant, Family.soothing},
      'Hydrates and soothes; great after shaving or irritation.',
      goodFor: {Concern.dryness, Concern.sensitivity, Concern.razorBumps},
    ),
    const Ingredient(
      'allantoin',
      'Allantoin',
      ['allantoin'],
      {Family.soothing},
      'Soothing and softening.',
      goodFor: {Concern.sensitivity, Concern.razorBumps},
    ),
    const Ingredient(
      'centella',
      'Centella asiatica (cica)',
      [
        'centella asiatica extract',
        'centella asiatica leaf extract',
        'madecassoside',
        'asiaticoside',
        'asiatic acid',
        'madecassic acid',
        'centella asiatica',
      ],
      {Family.soothing},
      'Calms redness and supports healing.',
      goodFor: {Concern.redness, Concern.sensitivity, Concern.acne},
    ),
    const Ingredient(
      'oat',
      'Colloidal oatmeal',
      [
        'avena sativa kernel flour',
        'colloidal oatmeal',
        'avena sativa (oat) kernel flour',
        'avena sativa kernel extract',
      ],
      {Family.soothing},
      'Proven to calm itchy, irritated skin.',
      goodFor: {Concern.sensitivity, Concern.dryness},
    ),
    const Ingredient(
      'aloe',
      'Aloe vera',
      [
        'aloe barbadensis leaf juice',
        'aloe barbadensis leaf extract',
        'aloe vera',
      ],
      {Family.soothing, Family.humectant},
      'Lightweight soothing hydration.',
    ),
    const Ingredient(
      'beta_glucan',
      'Beta-glucan',
      ['beta-glucan', 'beta glucan', 'oat beta glucan'],
      {Family.soothing, Family.humectant},
      'Soothing hydrator that supports barrier recovery.',
      goodFor: {Concern.sensitivity, Concern.dryness},
    ),
    const Ingredient(
      'bisabolol',
      'Bisabolol',
      ['bisabolol', 'alpha-bisabolol'],
      {Family.soothing},
      'Chamomile-derived calming ingredient.',
      goodFor: {Concern.redness},
    ),
    const Ingredient(
      'snail',
      'Snail mucin',
      ['snail secretion filtrate'],
      {Family.humectant, Family.soothing},
      'Hydrating and soothing; popular in K-beauty.',
    ),
    const Ingredient(
      'squalane',
      'Squalane',
      ['squalane'],
      {Family.emollient},
      'Lightweight, non-greasy oil that mimics skin\'s own lipids. Safe for fungal-acne-prone skin.',
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'petrolatum',
      'Petrolatum',
      ['petrolatum', 'white petrolatum', 'petroleum jelly'],
      {Family.occlusive},
      'The most effective water-loss blocker. Not comedogenic despite the myth.',
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'mineral_oil',
      'Mineral oil',
      ['mineral oil', 'paraffinum liquidum'],
      {Family.occlusive},
      'Inert, very low-irritation moisturizer. Cosmetic grade does not clog pores for most people.',
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'dimethicone',
      'Dimethicone',
      ['dimethicone', 'cyclopentasiloxane', 'cyclomethicone', 'dimethiconol'],
      {Family.occlusive, Family.emollient},
      'Silicone that smooths and protects. Well tolerated and non-comedogenic for most.',
      comedogenic: 1,
    ),
    const Ingredient(
      'shea',
      'Shea butter',
      [
        'butyrospermum parkii butter',
        'butyrospermum parkii (shea) butter',
        'shea butter',
        'vitellaria paradoxa butter',
      ],
      {Family.emollient, Family.occlusive},
      'Rich, nourishing butter for dry skin.',
      comedogenic: 0,
      fungalAcneTrigger: true,
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'jojoba',
      'Jojoba oil',
      [
        'simmondsia chinensis seed oil',
        'simmondsia chinensis (jojoba) seed oil',
        'jojoba oil',
      ],
      {Family.emollient},
      'A liquid wax similar to skin oil; low pore-clogging potential.',
      comedogenic: 2,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'fatty_alcohols',
      'Fatty alcohols (cetyl / cetearyl)',
      [
        'cetyl alcohol',
        'cetearyl alcohol',
        'stearyl alcohol',
        'behenyl alcohol',
      ],
      {Family.emollient},
      'These are "good" alcohols: waxy softeners, not drying. Ignore alcohol scaremongering.',
      comedogenic: 2,
    ),

    // ── Antioxidants & peptides ────────────────────────────────────────
    const Ingredient(
      'vit_e',
      'Vitamin E',
      ['tocopherol', 'tocopheryl acetate'],
      {Family.antioxidant},
      'Antioxidant that also stabilises vitamin C.',
      comedogenic: 2,
    ),
    const Ingredient(
      'ferulic',
      'Ferulic acid',
      ['ferulic acid'],
      {Family.antioxidant},
      'Antioxidant that boosts vitamin C & E stability.',
    ),
    const Ingredient(
      'green_tea',
      'Green tea extract',
      ['camellia sinensis leaf extract', 'epigallocatechin gallate'],
      {Family.antioxidant, Family.soothing},
      'Antioxidant with calming properties.',
      goodFor: {Concern.redness},
    ),
    const Ingredient(
      'resveratrol',
      'Resveratrol',
      ['resveratrol'],
      {Family.antioxidant},
      'Antioxidant often paired with retinoids.',
    ),
    const Ingredient(
      'peptides',
      'Peptides',
      [
        'palmitoyl tripeptide-1',
        'palmitoyl tetrapeptide-7',
        'palmitoyl pentapeptide-4',
        'acetyl hexapeptide-8',
        'acetyl hexapeptide-3',
        'palmitoyl tripeptide-5',
        'palmitoyl tripeptide-38',
        'copper tripeptide-1',
        'tripeptide-29',
      ],
      {Family.peptide},
      'Messenger molecules that support firmness. Gentle, modest evidence.',
      goodFor: {Concern.fineLines},
    ),
    const Ingredient(
      'caffeine',
      'Caffeine',
      ['caffeine'],
      {Family.caffeine, Family.antioxidant},
      'Temporarily de-puffs and tightens, popular in eye products.',
      goodFor: {Concern.darkCircles},
    ),

    // ── Sunscreen filters ──────────────────────────────────────────────
    const Ingredient(
      'zinc_oxide',
      'Zinc oxide',
      ['zinc oxide'],
      {Family.sunscreenMineral, Family.soothing},
      'Broad-spectrum mineral UV filter, very gentle. Can leave a white cast on deeper skin unless tinted.',
      goodFor: {Concern.sensitivity, Concern.redness, Concern.darkSpots},
    ),
    const Ingredient(
      'titanium_dioxide',
      'Titanium dioxide',
      ['titanium dioxide', 'ci 77891'],
      {Family.sunscreenMineral},
      'Mineral UV filter (also used as a white pigment).',
    ),
    const Ingredient(
      'avobenzone',
      'Avobenzone',
      ['butyl methoxydibenzoylmethane', 'avobenzone'],
      {Family.sunscreenChemical},
      'Key UVA filter.',
    ),
    const Ingredient(
      'octinoxate',
      'Octinoxate',
      ['ethylhexyl methoxycinnamate', 'octinoxate', 'octyl methoxycinnamate'],
      {Family.sunscreenChemical},
      'UVB filter.',
    ),
    const Ingredient(
      'octocrylene',
      'Octocrylene',
      ['octocrylene'],
      {Family.sunscreenChemical},
      'UVB filter that stabilises avobenzone.',
    ),
    const Ingredient(
      'homosalate',
      'Homosalate',
      ['homosalate'],
      {Family.sunscreenChemical},
      'UVB filter.',
    ),
    const Ingredient(
      'octisalate',
      'Octisalate',
      ['ethylhexyl salicylate', 'octisalate'],
      {Family.sunscreenChemical},
      'UVB filter.',
    ),
    const Ingredient(
      'oxybenzone',
      'Oxybenzone',
      ['benzophenone-3', 'oxybenzone'],
      {Family.sunscreenChemical},
      'Older broad-spectrum filter; a more common allergen than newer filters.',
      irritancy: 1,
    ),
    const Ingredient(
      'bemotrizinol',
      'Bemotrizinol (Tinosorb S)',
      [
        'bis-ethylhexyloxyphenol methoxyphenyl triazine',
        'bemotrizinol',
        'tinosorb s',
      ],
      {Family.sunscreenChemical},
      'Modern, photostable broad-spectrum filter. Invisible on all skin tones.',
    ),
    const Ingredient(
      'bisoctrizole',
      'Bisoctrizole (Tinosorb M)',
      [
        'methylene bis-benzotriazolyl tetramethylbutylphenol',
        'bisoctrizole',
        'tinosorb m',
      ],
      {Family.sunscreenChemical},
      'Modern, photostable broad-spectrum filter.',
    ),
    const Ingredient(
      'uvinul_a',
      'Uvinul A Plus',
      ['diethylamino hydroxybenzoyl hexyl benzoate'],
      {Family.sunscreenChemical},
      'Modern, stable UVA filter.',
    ),
    const Ingredient(
      'uvinul_t',
      'Uvinul T 150',
      ['ethylhexyl triazone'],
      {Family.sunscreenChemical},
      'Very efficient, stable UVB filter.',
    ),
    const Ingredient(
      'mexoryl',
      'Mexoryl SX / XL',
      [
        'terephthalylidene dicamphor sulfonic acid',
        'drometrizole trisiloxane',
        'ecamsule',
      ],
      {Family.sunscreenChemical},
      'Photostable UVA filters.',
    ),
    const Ingredient(
      'iscotrizinol',
      'Iscotrizinol (Uvasorb HEB)',
      ['diethylhexyl butamido triazone', 'iscotrizinol'],
      {Family.sunscreenChemical},
      'Stable UVB filter.',
    ),

    // ── Things to know about ───────────────────────────────────────────
    const Ingredient(
      'fragrance',
      'Fragrance',
      ['fragrance', 'parfum', 'aroma', 'perfume'],
      {Family.fragrance},
      'Adds scent only. A leading cause of skincare allergies; skip it if your skin is reactive.',
      irritancy: 2,
    ),
    const Ingredient(
      'fragrance_allergens',
      'Fragrance allergens',
      [
        'limonene',
        'linalool',
        'citronellol',
        'geraniol',
        'citral',
        'eugenol',
        'isoeugenol',
        'coumarin',
        'hexyl cinnamal',
        'benzyl salicylate',
        'benzyl benzoate',
        'benzyl cinnamate',
        'cinnamal',
        'cinnamyl alcohol',
        'farnesol',
        'hydroxycitronellal',
        'amyl cinnamal',
        'alpha-isomethyl ionone',
        'anise alcohol',
        'butylphenyl methylpropional',
      ],
      {Family.fragrance},
      'Scent components that must be labelled because they can trigger allergies.',
      irritancy: 1,
    ),
    const Ingredient(
      'essential_oils',
      'Essential oils',
      [
        'lavandula angustifolia oil',
        'lavandula angustifolia (lavender) oil',
        'lavender oil',
        'mentha piperita oil',
        'mentha piperita (peppermint) oil',
        'peppermint oil',
        'citrus limon peel oil',
        'citrus aurantium bergamia peel oil',
        'citrus aurantium dulcis peel oil',
        'citrus sinensis peel oil',
        'eucalyptus globulus leaf oil',
        'rosmarinus officinalis leaf oil',
        'cananga odorata flower oil',
        'pelargonium graveolens oil',
        'cymbopogon schoenanthus oil',
        'cinnamomum zeylanicum bark oil',
      ],
      {Family.essentialOil, Family.fragrance},
      'Natural doesn\'t mean gentle: essential oils are concentrated fragrance and common irritants. Citrus oils can react with sunlight.',
      irritancy: 2,
    ),
    const Ingredient(
      'menthol',
      'Menthol / camphor',
      ['menthol', 'camphor', 'menthyl lactate'],
      {Family.fragrance},
      'Creates a cooling "tingle" that is actually mild irritation.',
      irritancy: 2,
    ),
    const Ingredient(
      'denat_alcohol',
      'Drying alcohol',
      [
        'alcohol denat.',
        'alcohol denat',
        'alcohol',
        'sd alcohol',
        'sd alcohol 40',
        'ethanol',
        'isopropyl alcohol',
        'denatured alcohol',
      ],
      {Family.dryingAlcohol},
      'High up the list it can dry and irritate; low down it\'s usually just helping a formula absorb.',
      irritancy: 1,
    ),
    const Ingredient(
      'sls',
      'Sodium lauryl sulfate',
      ['sodium lauryl sulfate', 'ammonium lauryl sulfate'],
      {Family.harshSurfactant},
      'A strong cleanser that can strip and irritate, especially dry or sensitive skin.',
      irritancy: 2,
      comedogenic: 3,
    ),
    const Ingredient(
      'sles',
      'Sodium laureth sulfate',
      ['sodium laureth sulfate'],
      {Family.harshSurfactant},
      'Milder than SLS but can still be drying for some.',
      irritancy: 1,
    ),
    const Ingredient(
      'mi',
      'Methylisothiazolinone',
      ['methylisothiazolinone', 'methylchloroisothiazolinone'],
      {Family.allergenPreservative},
      'Preservative that is a well-known contact allergen in leave-on products.',
      irritancy: 2,
    ),
    const Ingredient(
      'formaldehyde_releasers',
      'Formaldehyde-releasing preservative',
      [
        'dmdm hydantoin',
        'quaternium-15',
        'imidazolidinyl urea',
        'diazolidinyl urea',
        'bronopol',
        '2-bromo-2-nitropropane-1,3-diol',
        'sodium hydroxymethylglycinate',
      ],
      {Family.allergenPreservative},
      'Preservatives that can trigger allergies in sensitive people.',
      irritancy: 2,
    ),
    const Ingredient(
      'parabens',
      'Parabens',
      ['methylparaben', 'propylparaben', 'ethylparaben', 'butylparaben'],
      {Family.preservative},
      'Among the most studied, lowest-allergy preservatives. Considered safe at cosmetic levels.',
    ),
    const Ingredient(
      'phenoxyethanol',
      'Phenoxyethanol',
      ['phenoxyethanol'],
      {Family.preservative},
      'A common, well-tolerated preservative. Keeps products safe from microbes.',
    ),
    const Ingredient(
      'scrub_particles',
      'Physical scrub particles',
      [
        'juglans regia shell powder',
        'walnut shell powder',
        'prunus armeniaca seed powder',
        'apricot seed powder',
        'pumice',
        'polyethylene',
      ],
      {Family.physicalExfoliant},
      'Jagged particles can cause micro-tears and irritation, especially on acne or sensitive skin.',
      irritancy: 2,
    ),

    // ── Pore-clogging & fungal-acne relevant emollients ────────────────
    const Ingredient(
      'coconut_oil',
      'Coconut oil',
      ['cocos nucifera oil', 'cocos nucifera (coconut) oil', 'coconut oil'],
      {Family.emollient},
      'Rich and moisturising but highly pore-clogging for acne-prone skin.',
      comedogenic: 4,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'ipm',
      'Isopropyl myristate',
      ['isopropyl myristate'],
      {Family.emollient},
      'Silky emollient with a high pore-clogging rating.',
      comedogenic: 5,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'ipp',
      'Isopropyl palmitate',
      ['isopropyl palmitate'],
      {Family.emollient},
      'Emollient with a high pore-clogging rating.',
      comedogenic: 4,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'ipis',
      'Isopropyl isostearate',
      ['isopropyl isostearate', 'isostearyl isostearate'],
      {Family.emollient},
      'Emollient with a high pore-clogging rating.',
      comedogenic: 5,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'myristyl',
      'Myristyl myristate / lactate',
      ['myristyl myristate', 'myristyl lactate'],
      {Family.emollient},
      'Emollient with a high pore-clogging rating.',
      comedogenic: 5,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'ethylhexyl_palmitate',
      'Ethylhexyl palmitate',
      [
        'ethylhexyl palmitate',
        'octyl palmitate',
        'ethylhexyl stearate',
        'octyl stearate',
      ],
      {Family.emollient},
      'Emollient ester that can clog pores for some.',
      comedogenic: 4,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'cocoa_butter',
      'Cocoa butter',
      [
        'theobroma cacao seed butter',
        'theobroma cacao (cocoa) seed butter',
        'cocoa butter',
      ],
      {Family.emollient, Family.occlusive},
      'Rich butter with a high pore-clogging rating.',
      comedogenic: 4,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'wheat_germ',
      'Wheat germ oil',
      [
        'triticum vulgare germ oil',
        'triticum vulgare (wheat) germ oil',
        'wheat germ oil',
      ],
      {Family.emollient},
      'Very pore-clogging for acne-prone skin.',
      comedogenic: 5,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'algae',
      'Algae / seaweed extract',
      [
        'algae extract',
        'red algae extract',
        'chondrus crispus extract',
        'carrageenan',
        'laminaria digitata extract',
      ],
      {Family.humectant},
      'Hydrating, but some algae extracts rate high for clogging pores.',
      comedogenic: 4,
    ),
    const Ingredient(
      'laureth4',
      'Laureth-4',
      ['laureth-4'],
      {Family.emollient},
      'Emulsifier with a high pore-clogging rating.',
      comedogenic: 5,
    ),
    const Ingredient(
      'acetylated_lanolin',
      'Acetylated lanolin',
      ['acetylated lanolin', 'acetylated lanolin alcohol', 'peg-16 lanolin'],
      {Family.emollient},
      'Can clog pores for acne-prone skin.',
      comedogenic: 4,
    ),
    const Ingredient(
      'lanolin',
      'Lanolin',
      ['lanolin', 'lanolin alcohol'],
      {Family.occlusive, Family.emollient},
      'Excellent occlusive for very dry skin; occasional allergen.',
      comedogenic: 1,
      irritancy: 1,
    ),
    const Ingredient(
      'flaxseed',
      'Flaxseed oil',
      ['linum usitatissimum seed oil', 'linseed oil'],
      {Family.emollient},
      'Pore-clogging rating is high.',
      comedogenic: 4,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'soybean_oil',
      'Soybean oil',
      ['glycine soja oil', 'glycine soja (soybean) oil', 'soybean oil'],
      {Family.emollient},
      'Moderate pore-clogging potential.',
      comedogenic: 3,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'olive_oil',
      'Olive oil',
      [
        'olea europaea fruit oil',
        'olea europaea (olive) fruit oil',
        'olive oil',
      ],
      {Family.emollient},
      'High in oleic acid, which can weaken the barrier for some.',
      comedogenic: 2,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'argan',
      'Argan oil',
      ['argania spinosa kernel oil', 'argan oil'],
      {Family.emollient},
      'Nourishing oil with low pore-clogging potential.',
      fungalAcneTrigger: true,
      goodFor: {Concern.dryness},
    ),
    const Ingredient(
      'rosehip',
      'Rosehip oil',
      ['rosa canina fruit oil', 'rosa rubiginosa seed oil', 'rosehip oil'],
      {Family.emollient, Family.antioxidant},
      'Lightweight oil with natural fatty acids and antioxidants.',
      comedogenic: 1,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'sunflower',
      'Sunflower seed oil',
      ['helianthus annuus seed oil', 'helianthus annuus (sunflower) seed oil'],
      {Family.emollient, Family.barrier},
      'Linoleic-acid-rich oil that supports the barrier.',
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'fatty_acids',
      'Fatty acids',
      [
        'stearic acid',
        'palmitic acid',
        'myristic acid',
        'lauric acid',
        'oleic acid',
      ],
      {Family.emollient},
      'Building blocks of skin lipids; some are mildly pore-clogging and feed fungal acne.',
      comedogenic: 2,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'glyceryl_stearate',
      'Glyceryl stearate',
      ['glyceryl stearate', 'glyceryl stearate se', 'peg-100 stearate'],
      {Family.emollient},
      'Common emulsifier; generally well tolerated.',
      comedogenic: 1,
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'polysorbates',
      'Polysorbates',
      ['polysorbate 20', 'polysorbate 40', 'polysorbate 60', 'polysorbate 80'],
      {Family.emollient},
      'Emulsifiers. Fine for most skin, but flagged for fungal acne.',
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'ferments',
      'Ferment filtrates',
      [
        'galactomyces ferment filtrate',
        'saccharomyces ferment filtrate',
        'bifida ferment lysate',
        'lactobacillus ferment',
      ],
      {Family.humectant, Family.soothing},
      'Fermented hydrators; flagged by some for fungal acne.',
      fungalAcneTrigger: true,
    ),
    const Ingredient(
      'caprylic_triglyceride',
      'Caprylic/capric triglyceride',
      ['caprylic/capric triglyceride', 'caprylic capric triglyceride'],
      {Family.emollient},
      'Light, well-tolerated emollient from coconut (does not share coconut oil\'s clogging rating).',
      comedogenic: 1,
    ),

    // ── Base ingredients ───────────────────────────────────────────────
    const Ingredient(
      'water',
      'Water',
      [
        'water',
        'aqua',
        'eau',
        'aqua/water/eau',
        'aqua (water)',
        'water (aqua)',
      ],
      {},
      'The base of most formulas.',
    ),
    const Ingredient(
      'butylene_glycol',
      'Butylene / propylene glycol',
      [
        'butylene glycol',
        'propylene glycol',
        'propanediol',
        'pentylene glycol',
        '1,2-hexanediol',
        'caprylyl glycol',
      ],
      {Family.humectant},
      'Lightweight hydrating solvents.',
    ),
    const Ingredient(
      'xanthan',
      'Thickeners',
      [
        'xanthan gum',
        'carbomer',
        'hydroxyethylcellulose',
        'acrylates/c10-30 alkyl acrylate crosspolymer',
        'sodium polyacrylate',
      ],
      {},
      'Give the product its texture.',
    ),
    const Ingredient(
      'ph_adjusters',
      'pH adjusters',
      [
        'sodium hydroxide',
        'citric acid',
        'triethanolamine',
        'tromethamine',
        'sodium citrate',
        'arginine',
      ],
      {},
      'Keep the formula at a skin-friendly pH. Harmless at these levels.',
    ),
    const Ingredient(
      'chelators',
      'Chelating agents',
      [
        'disodium edta',
        'tetrasodium edta',
        'trisodium ethylenediamine disuccinate',
        'sodium phytate',
      ],
      {},
      'Help keep the formula stable.',
    ),
    const Ingredient(
      'ethylhexylglycerin',
      'Ethylhexylglycerin',
      ['ethylhexylglycerin'],
      {Family.preservative},
      'Preservative booster and skin conditioner.',
    ),
    const Ingredient(
      'sodium_benzoate',
      'Sodium benzoate / potassium sorbate',
      [
        'sodium benzoate',
        'potassium sorbate',
        'benzyl alcohol',
        'dehydroacetic acid',
        'sodium dehydroacetate',
        'chlorphenesin',
      ],
      {Family.preservative},
      'Common preservatives that keep the product safe.',
    ),
  ];

  static final Map<String, Ingredient> _byAlias = {
    for (final ing in all)
      for (final alias in ing.aliases) alias: ing,
  };

  /// Aliases sorted longest-first so substring matching prefers the most
  /// specific name ("glycolic acid" before "acid"-like fragments).
  static final List<MapEntry<String, Ingredient>> _aliasesByLength = [
    for (final ing in all)
      for (final alias in ing.aliases)
        if (alias.length >= 6 && !_exactOnly.contains(alias))
          MapEntry(alias, ing),
  ]..sort((a, b) => b.key.length.compareTo(a.key.length));

  /// Generic words that must match a whole token, otherwise "myristyl
  /// alcohol" (a fatty alcohol) would be mistaken for drying alcohol and
  /// "rosa damascena flower water" for plain water.
  static const _exactOnly = {
    'alcohol',
    'water',
    'galactose',
    'sulfur',
    'sulphur',
    'perfume',
    'ethanol',
  };

  static Ingredient? byId(String id) =>
      all.where((i) => i.id == id).firstOrNull;

  /// Matches a single normalized INCI token.
  static Ingredient? match(String token) {
    final exact = _byAlias[token];
    if (exact != null) return exact;

    // Drop parenthetical descriptors: "butyrospermum parkii (shea) butter".
    final withoutParens = token
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final stripped = _byAlias[withoutParens];
    if (stripped != null) return stripped;

    for (final e in _aliasesByLength) {
      if (_containsWord(token, e.key)) return e.value;
    }
    return null;
  }

  static bool _containsWord(String haystack, String needle) {
    final idx = haystack.indexOf(needle);
    if (idx < 0) return false;
    final before = idx == 0 ? ' ' : haystack[idx - 1];
    final afterIdx = idx + needle.length;
    final after = afterIdx >= haystack.length ? ' ' : haystack[afterIdx];
    bool boundary(String c) => !RegExp(r'[a-z0-9]').hasMatch(c);
    return boundary(before) && boundary(after);
  }
}
