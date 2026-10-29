/// Offline reference values, not a prescription or clinical diagnosis.
class AkgReference {
  final String group;
  final int energy, protein, fat, carbohydrate, fiber, water;

  /// Iron in mg, vitamin A in RE (retinol equivalents), vitamin D in µg.
  /// Units match the official AKG table; no conversion to supplement IU.
  final double ironMg;
  final int vitaminARe, vitaminDMcg;
  const AkgReference(
    this.group,
    this.energy,
    this.protein,
    this.fat,
    this.carbohydrate,
    this.fiber,
    this.water, {
    required this.ironMg,
    required this.vitaminARe,
    required this.vitaminDMcg,
  });
  static const source = 'Permenkes 28/2019, Lampiran I';
  static AkgReference? forMonths(int months) {
    if (months < 0 || months >= 84) return null;
    if (months < 6) {
      return const AkgReference(
        '0–5 bulan',
        550,
        9,
        31,
        59,
        0,
        700,
        ironMg: 0.3,
        vitaminARe: 375,
        vitaminDMcg: 10,
      );
    }
    if (months < 12) {
      return const AkgReference(
        '6–11 bulan',
        800,
        15,
        35,
        105,
        11,
        900,
        ironMg: 11,
        vitaminARe: 400,
        vitaminDMcg: 10,
      );
    }
    if (months < 48) {
      return const AkgReference(
        '1–3 tahun',
        1350,
        20,
        45,
        215,
        19,
        1150,
        ironMg: 7,
        vitaminARe: 400,
        vitaminDMcg: 15,
      );
    }
    return const AkgReference(
      '4–6 tahun',
      1400,
      25,
      50,
      220,
      20,
      1450,
      ironMg: 10,
      vitaminARe: 450,
      vitaminDMcg: 15,
    );
  }

  double percentEnergy(double intake) => percentage(intake, energy);
  double percentProtein(double intake) => percentage(intake, protein);
  double percentIron(double intakeMg) => percentage(intakeMg, ironMg);
  double percentVitaminA(double intakeRe) => percentage(intakeRe, vitaminARe);
  double percentVitaminD(double intakeMcg) =>
      percentage(intakeMcg, vitaminDMcg);
  static double percentage(double intake, num reference) {
    if (!intake.isFinite || intake < 0) {
      throw ArgumentError('Asupan tidak valid');
    }
    return intake / reference * 100;
  }
}

enum PmtKind { outsideAge, referral, assessment, candidate, education }

class PmtRange {
  final int energyMin, energyMax;
  final double proteinMin, proteinMax;
  const PmtRange(
    this.energyMin,
    this.energyMax,
    this.proteinMin,
    this.proteinMax,
  );
}

class PmtAdvice {
  final PmtKind kind;
  final String message;
  final PmtRange? range;
  const PmtAdvice(this.kind, this.message, [this.range]);
  static const source = 'Kemenkes HK.02.02/B/576/2025, hlm. 7, 22, 40';
  static PmtAdvice assess({
    required int months,
    double? wfaZ,
    double? wfhZ,
    double? muac,
    bool oedema = false,
    bool redFlags = false,
    bool allergies = false,
    bool growthConcern = false,
  }) {
    if (oedema ||
        redFlags ||
        (wfhZ != null && wfhZ.isFinite && wfhZ < -3) ||
        (months >= 6 &&
            months < 60 &&
            muac != null &&
            muac.isFinite &&
            muac > 0 &&
            muac < 11.5)) {
      return const PmtAdvice(
        PmtKind.referral,
        'Perlu pemeriksaan tenaga kesehatan segera; PMT biasa tidak menggantikan tata laksana gizi buruk atau penyakit.',
      );
    }
    if (months < 6 || months >= 60) {
      return const PmtAdvice(
        PmtKind.outsideAge,
        'Di luar sasaran PMT lokal balita 6–59 bulan. Bayi <6 bulan memerlukan penilaian menyusui oleh tenaga kesehatan.',
      );
    }
    if (allergies) {
      return const PmtAdvice(
        PmtKind.assessment,
        'Riwayat alergi: menu dan tata laksana khusus ditentukan tenaga kesehatan.',
      );
    }
    if ((wfaZ == null && wfhZ == null && !growthConcern && muac == null) ||
        (wfaZ != null && !wfaZ.isFinite) ||
        (wfhZ != null && !wfhZ.isFinite) ||
        (muac != null && (!muac.isFinite || muac <= 0))) {
      return const PmtAdvice(
        PmtKind.assessment,
        'Data belum cukup/valid. Gunakan pengukuran disetujui terbaru dan pemeriksaan tenaga kesehatan.',
      );
    }
    if (wfhZ != null && wfhZ > 2) {
      return const PmtAdvice(
        PmtKind.assessment,
        'Indikator menunjukkan berat badan berlebih. Konfirmasi pengukuran dan kebutuhan gizi dengan tenaga kesehatan sebelum menentukan PMT.',
      );
    }
    if ((wfaZ != null && wfaZ < -2) ||
        (wfhZ != null && wfhZ >= -3 && wfhZ < -2) ||
        (muac != null && muac >= 11.5 && muac < 12.5) ||
        growthConcern) {
      final range = months < 12
          ? const PmtRange(175, 200, 3.5, 8)
          : months < 24
          ? const PmtRange(225, 275, 4.5, 11)
          : const PmtRange(300, 450, 6, 18);
      return PmtAdvice(
        PmtKind.candidate,
        'Calon sasaran untuk dikonfirmasi dokter/tenaga gizi. Rentang PMT kelompok umur per hari; bukan resep individual.',
        range,
      );
    }
    return const PmtAdvice(
      PmtKind.education,
      'Indikator tersedia belum menunjukkan kriteria PMT lokal. Lanjutkan pemantauan; stunting saja bukan penentu PMT otomatis.',
    );
  }
}
