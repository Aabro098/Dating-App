import 'package:viora/Services/AppConfigService.dart';

class ProfileConstants {
  ProfileConstants._();

  static final zodiacStrings = [
    "Aries",
    "Taurus",
    "Gemini",
    "Cancer",
    "Leo",
    "Virgo",
    "Libra",
    "Scorpio",
    "Sagittarius",
    "Capricorn",
    "Aquarius",
    "Pisces",
  ];

  static final interestStrings = AppConfigService.interests;

  static final dietStrings = ["Vegan", "Vegetarian", "Non-Vegetarian"];

  static final religionStrings = [
    "Hindu",
    "Muslim",
    "Christian",
    "Sikh",
    "Buddhist",
    "Jain",
    "Atheist",
    "Other",
  ];

  static final relationTypeStrings = [
    "Excitement",
    "Long Term",
    "Open to anything",
    "Short Term",
    "Undecided",
    "Virtual",
    "No String attached",
  ];

  static final orientationStrings = [
    "Bisexual",
    "Gay",
    "Straight",
    "Lesbian",
    "Queer",
    "Asexual",
  ];

  static final drinkingStrings = ["Yes", "No", "Occasional"];

  static final smokerStrings = ["Yes", "No", "Occasional"];

  static final maritalStrings = ["Single", "Married", "Divorced", "Separated"];

  static final messagePermissionStrings = ["All", "Matched/ Like"];
}
