import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class Wilaya {
  final int code;
  final String ar; // canonical value stored on the server
  final String fr;
  final double lat;
  final double lon;
  const Wilaya(this.code, this.ar, this.fr, this.lat, this.lon);

  String label(String lang) => lang == 'ar' ? '${_two(code)} - $ar' : '${_two(code)} - $fr';
  String name(String lang) => lang == 'ar' ? ar : fr;
  LatLng get point => LatLng(lat, lon);
}

String _two(int n) => n < 10 ? '0$n' : '$n';

const List<Wilaya> kWilayas = [
  Wilaya(1, 'أدرار', 'Adrar', 27.87, -0.29),
  Wilaya(2, 'الشلف', 'Chlef', 36.16, 1.33),
  Wilaya(3, 'الأغواط', 'Laghouat', 33.80, 2.88),
  Wilaya(4, 'أم البواقي', 'Oum El Bouaghi', 35.88, 7.11),
  Wilaya(5, 'باتنة', 'Batna', 35.56, 6.17),
  Wilaya(6, 'بجاية', 'Béjaïa', 36.75, 5.06),
  Wilaya(7, 'بسكرة', 'Biskra', 34.85, 5.73),
  Wilaya(8, 'بشار', 'Béchar', 31.62, -2.22),
  Wilaya(9, 'البليدة', 'Blida', 36.47, 2.83),
  Wilaya(10, 'البويرة', 'Bouira', 36.37, 3.90),
  Wilaya(11, 'تمنراست', 'Tamanrasset', 22.79, 5.52),
  Wilaya(12, 'تبسة', 'Tébessa', 35.40, 8.12),
  Wilaya(13, 'تلمسان', 'Tlemcen', 34.88, -1.32),
  Wilaya(14, 'تيارت', 'Tiaret', 35.37, 1.32),
  Wilaya(15, 'تيزي وزو', 'Tizi Ouzou', 36.71, 4.05),
  Wilaya(16, 'الجزائر', 'Alger', 36.75, 3.06),
  Wilaya(17, 'الجلفة', 'Djelfa', 34.67, 3.26),
  Wilaya(18, 'جيجل', 'Jijel', 36.82, 5.77),
  Wilaya(19, 'سطيف', 'Sétif', 36.19, 5.41),
  Wilaya(20, 'سعيدة', 'Saïda', 34.83, 0.15),
  Wilaya(21, 'سكيكدة', 'Skikda', 36.88, 6.91),
  Wilaya(22, 'سيدي بلعباس', 'Sidi Bel Abbès', 35.19, -0.63),
  Wilaya(23, 'عنابة', 'Annaba', 36.90, 7.77),
  Wilaya(24, 'قالمة', 'Guelma', 36.46, 7.43),
  Wilaya(25, 'قسنطينة', 'Constantine', 36.37, 6.61),
  Wilaya(26, 'المدية', 'Médéa', 36.26, 2.75),
  Wilaya(27, 'مستغانم', 'Mostaganem', 35.93, 0.09),
  Wilaya(28, 'المسيلة', "M'Sila", 35.70, 4.54),
  Wilaya(29, 'معسكر', 'Mascara', 35.40, 0.14),
  Wilaya(30, 'ورقلة', 'Ouargla', 31.95, 5.32),
  Wilaya(31, 'وهران', 'Oran', 35.70, -0.63),
  Wilaya(32, 'البيض', 'El Bayadh', 33.68, 1.02),
  Wilaya(33, 'إليزي', 'Illizi', 26.51, 8.48),
  Wilaya(34, 'برج بوعريريج', 'Bordj Bou Arréridj', 36.07, 4.76),
  Wilaya(35, 'بومرداس', 'Boumerdès', 36.76, 3.48),
  Wilaya(36, 'الطارف', 'El Tarf', 36.77, 8.31),
  Wilaya(37, 'تندوف', 'Tindouf', 27.67, -8.15),
  Wilaya(38, 'تيسمسيلت', 'Tissemsilt', 35.61, 1.81),
  Wilaya(39, 'الوادي', 'El Oued', 33.37, 6.86),
  Wilaya(40, 'خنشلة', 'Khenchela', 35.43, 7.14),
  Wilaya(41, 'سوق أهراس', 'Souk Ahras', 36.29, 7.95),
  Wilaya(42, 'تيبازة', 'Tipaza', 36.59, 2.45),
  Wilaya(43, 'ميلة', 'Mila', 36.45, 6.26),
  Wilaya(44, 'عين الدفلى', 'Aïn Defla', 36.26, 1.97),
  Wilaya(45, 'النعامة', 'Naâma', 33.27, -0.31),
  Wilaya(46, 'عين تموشنت', 'Aïn Témouchent', 35.30, -1.14),
  Wilaya(47, 'غرداية', 'Ghardaïa', 32.49, 3.67),
  Wilaya(48, 'غليزان', 'Relizane', 35.74, 0.56),
  Wilaya(49, 'تيميمون', 'Timimoun', 29.26, 0.23),
  Wilaya(50, 'برج باجي مختار', 'Bordj Badji Mokhtar', 21.33, 0.95),
  Wilaya(51, 'أولاد جلال', 'Ouled Djellal', 34.43, 5.07),
  Wilaya(52, 'بني عباس', 'Béni Abbès', 30.13, -2.17),
  Wilaya(53, 'عين صالح', 'In Salah', 27.20, 2.48),
  Wilaya(54, 'عين قزام', 'In Guezzam', 19.57, 5.77),
  Wilaya(55, 'تقرت', 'Touggourt', 33.10, 6.06),
  Wilaya(56, 'جانت', 'Djanet', 24.55, 9.48),
  Wilaya(57, 'المغير', "El M'Ghair", 33.95, 5.92),
  Wilaya(58, 'المنيعة', 'El Menia', 30.58, 2.88),
];

const String kDefaultWilaya = 'الجزائر';

Wilaya? wilayaByAr(String? ar) {
  if (ar == null) return null;
  for (final w in kWilayas) {
    if (w.ar == ar) return w;
  }
  return null;
}

/// Localized display name for a wilaya value stored on the server (Arabic name).
String wilayaDisplay(String? ar, String lang) {
  if (ar == null || ar.isEmpty) return '';
  final w = wilayaByAr(ar);
  return w == null ? ar : w.name(lang);
}

/// Nearest wilaya (by capital) for a coordinate. Approximate - used as a default only.
Wilaya nearestWilaya(LatLng p) {
  Wilaya best = kWilayas.first;
  double bestD = double.infinity;
  for (final w in kWilayas) {
    final dLat = (w.lat - p.latitude) * math.pi / 180;
    final dLon = (w.lon - p.longitude) * math.pi / 180 * math.cos(p.latitude * math.pi / 180);
    final d = dLat * dLat + dLon * dLon;
    if (d < bestD) {
      bestD = d;
      best = w;
    }
  }
  return best;
}
