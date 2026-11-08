import 'package:maktub_core/maktub_core.dart';

String planTypeLabel(PlanType type) => switch (type) {
  PlanType.regular => 'Regular',
  PlanType.test => 'Test',
};
