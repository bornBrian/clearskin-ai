import 'package:clearskin_ai/data/models/profile.dart';

UserProfile profile({
  SkinType skinType = SkinType.normal,
  Sensitivity sensitivity = Sensitivity.low,
  Set<Concern> concerns = const {},
  Set<Goal> goals = const {},
  RoutineComplexity complexity = RoutineComplexity.balanced,
  bool pregnant = false,
  bool shaves = false,
  SkinTone? tone,
  AgeRange age = AgeRange.a25,
  Gender gender = Gender.woman,
}) => UserProfile(
  name: 'Test',
  gender: gender,
  ageRange: age,
  skinType: skinType,
  sensitivity: sensitivity,
  concerns: concerns,
  goals: goals,
  complexity: complexity,
  budget: Budget.mid,
  createdAt: DateTime(2026, 1, 1),
  pregnantOrNursing: pregnant,
  shaves: shaves,
  skinTone: tone,
);
