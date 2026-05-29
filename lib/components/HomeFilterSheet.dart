import 'dart:ui';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';
import 'package:viora/Services/Global.dart';

/// Filter state model - session specific (not persisted)
class HomeFilterState {
  final RangeValues ageRange;
  final double maxDistance;
  final bool showAllPeople;
  final Set<String> relationTypes;
  final double height;
  final Set<String> dietTypes;
  // Premium filters
  final int minPhotos;
  final bool hasBio;
  final bool onlyOnlineUsers;
  final bool onlyVerifiedProfiles;

  const HomeFilterState({
    this.ageRange = const RangeValues(18, 100),
    this.maxDistance = 150,
    this.showAllPeople = true,
    this.relationTypes = const {},
    this.height = 120, // Min height in cm
    this.dietTypes = const {},
    this.minPhotos = 1,
    this.hasBio = false,
    this.onlyOnlineUsers = false,
    this.onlyVerifiedProfiles = false,
  });

  HomeFilterState copyWith({
    RangeValues? ageRange,
    double? maxDistance,
    bool? showAllPeople,
    Set<String>? relationTypes,
    double? height,
    Set<String>? dietTypes,
    int? minPhotos,
    bool? hasBio,
    bool? onlyOnlineUsers,
    bool? onlyVerifiedProfiles,
  }) {
    return HomeFilterState(
      ageRange: ageRange ?? this.ageRange,
      maxDistance: maxDistance ?? this.maxDistance,
      showAllPeople: showAllPeople ?? this.showAllPeople,
      relationTypes: relationTypes ?? this.relationTypes,
      height: height ?? this.height,
      dietTypes: dietTypes ?? this.dietTypes,
      minPhotos: minPhotos ?? this.minPhotos,
      hasBio: hasBio ?? this.hasBio,
      onlyOnlineUsers: onlyOnlineUsers ?? this.onlyOnlineUsers,
      onlyVerifiedProfiles: onlyVerifiedProfiles ?? this.onlyVerifiedProfiles,
    );
  }

  /// Check if any filter is active
  bool get hasActiveFilters {
    return ageRange != const RangeValues(18, 100) ||
        maxDistance < 150 ||
        !showAllPeople ||
        relationTypes.isNotEmpty ||
        height > 120 ||
        dietTypes.isNotEmpty ||
        minPhotos > 1 ||
        hasBio ||
        onlyOnlineUsers ||
        onlyVerifiedProfiles;
  }

  static List<String> _sortedStrings(Set<String> s) {
    final list = s.toList()..sort();
    return list;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HomeFilterState &&
        other.ageRange.start == ageRange.start &&
        other.ageRange.end == ageRange.end &&
        other.maxDistance == maxDistance &&
        other.showAllPeople == showAllPeople &&
        listEquals(
          _sortedStrings(other.relationTypes),
          _sortedStrings(relationTypes),
        ) &&
        other.height == height &&
        listEquals(
          _sortedStrings(other.dietTypes),
          _sortedStrings(dietTypes),
        ) &&
        other.minPhotos == minPhotos &&
        other.hasBio == hasBio &&
        other.onlyOnlineUsers == onlyOnlineUsers &&
        other.onlyVerifiedProfiles == onlyVerifiedProfiles;
  }

  @override
  int get hashCode => Object.hash(
    ageRange.start,
    ageRange.end,
    maxDistance,
    showAllPeople,
    Object.hashAll(_sortedStrings(relationTypes)),
    Object.hashAll(_sortedStrings(dietTypes)),
    height,
    minPhotos,
    hasBio,
    onlyOnlineUsers,
    onlyVerifiedProfiles,
  );
}

/// Relation type options
const List<String> kRelationTypes = [
  'Long Term',
  'Short Term',
  'Excitement',
  'Open to Anything',
];

/// Diet type options
const List<String> kDietTypes = ['Vegetarian', 'Non-vegetarian', 'Vegan'];

/// Helper to convert height in cm to feet'inches format
String heightToFeetInches(double cm) {
  final totalInches = cm / 2.54;
  final feet = (totalInches / 12).floor();
  final inches = (totalInches % 12).round();
  return "${cm.toInt()}cm (${feet}'${inches})";
}

/// Shows the filter bottom sheet
Future<HomeFilterState?> showHomeFilterSheet({
  required BuildContext context,
  required HomeFilterState currentFilters,
  int? currentUserPhotoCount,
  bool isTopPicksActive = false,
}) {
  return showModalBottomSheet<HomeFilterState>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFF1F1F1F).withOpacity(0.25),
    builder: (context) => _HomeFilterSheet(
      initialFilters: currentFilters,
      currentUserPhotoCount: currentUserPhotoCount ?? 0,
      isTopPicksActive: isTopPicksActive,
    ),
  );
}

class _HomeFilterSheet extends HookWidget {
  final HomeFilterState initialFilters;
  final int currentUserPhotoCount;
  final bool isTopPicksActive;

  const _HomeFilterSheet({
    required this.initialFilters,
    required this.currentUserPhotoCount,
    required this.isTopPicksActive,
  });

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);

    // Check if location permission is granted
    final hasLocationPermission = useState(false);

    useEffect(() {
      Future<void> checkPermission() async {
        final status = await Permission.location.status;
        final denied = globals.prefs.locationPermissionDenied.value;
        hasLocationPermission.value = status.isGranted && !denied;
      }

      checkPermission();
      return null;
    }, []);

    // State
    final ageRange = useState(initialFilters.ageRange);
    final maxDistance = useState(initialFilters.maxDistance);
    final showAllPeople = useState(initialFilters.showAllPeople);
    final relationTypes = useState(
      Set<String>.from(initialFilters.relationTypes),
    );
    final height = useState(initialFilters.height);
    final dietTypes = useState(Set<String>.from(initialFilters.dietTypes));
    final minPhotos = useState(initialFilters.minPhotos);
    final hasBio = useState(initialFilters.hasBio);
    final onlyOnlineUsers = useState(initialFilters.onlyOnlineUsers);
    final onlyVerifiedProfiles = useState(initialFilters.onlyVerifiedProfiles);
    final showMoreFilters = useState(false);

    // Session-based filter change tracking
    final hasChangesInCurrentSession = useState(false);

    void markChange() {
      hasChangesInCurrentSession.value = true;
    }

    // Animation controller for expand/collapse
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 300),
    );

    // Sheet height changes based on expanded state
    final baseHeight = MediaQuery.of(context).size.height * 0.75;
    final expandedHeight = MediaQuery.of(context).size.height * 0.95;

    useEffect(() {
      if (showMoreFilters.value) {
        animationController.forward();
      } else {
        animationController.reverse();
      }
      return null;
    }, [showMoreFilters.value]);

    void toggleRelationType(String type) {
      final current = Set<String>.from(relationTypes.value);
      if (current.contains(type)) {
        current.remove(type);
      } else {
        current.add(type);
      }
      relationTypes.value = current;
      markChange();
    }

    void toggleDietType(String type) {
      final current = Set<String>.from(dietTypes.value);
      if (current.contains(type)) {
        current.remove(type);
      } else {
        current.add(type);
      }
      dietTypes.value = current;
      markChange();
    }

    void applyFilters() {
      final filters = HomeFilterState(
        ageRange: ageRange.value,
        maxDistance: maxDistance.value,
        showAllPeople: showAllPeople.value,
        relationTypes: relationTypes.value,
        height: height.value,
        dietTypes: dietTypes.value,
        minPhotos: minPhotos.value,
        hasBio: hasBio.value,
        onlyOnlineUsers: onlyOnlineUsers.value,
        onlyVerifiedProfiles: onlyVerifiedProfiles.value,
      );
      Navigator.of(context).pop(filters);
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
      child: AnimatedBuilder(
        animation: animationController,
        builder: (context, child) {
          final currentHeight =
              baseHeight +
              (expandedHeight - baseHeight) * animationController.value;

          return Stack(
            children: [
              // Main Sheet
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: currentHeight,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(23),
                      topRight: Radius.circular(23),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Drag Handle & Collapse Button
                      _buildHeader(
                        context,
                        showMoreFilters,
                        ageRange,
                        maxDistance,
                        showAllPeople,
                        relationTypes,
                        height,
                        dietTypes,
                        minPhotos,
                        hasBio,
                        onlyOnlineUsers,
                        onlyVerifiedProfiles,
                        applyFilters,
                        hasChangesInCurrentSession,
                        markChange,
                      ),

                      // Scrollable Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: getProportionateScreenWidth(23),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),

                              // Age Range
                              _buildAgeSection(ageRange, markChange),
                              const SizedBox(height: 24),

                              // Distance (only show if location permission is granted)
                              if (hasLocationPermission.value) ...[
                                _buildDistanceSection(
                                  maxDistance,
                                  showAllPeople,
                                  markChange,
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Relation Type
                              _buildRelationTypeSection(
                                relationTypes,
                                toggleRelationType,
                              ),
                              const SizedBox(height: 24),

                              // Height
                              _buildHeightSection(height, markChange),
                              const SizedBox(height: 24),

                              // Diet
                              _buildDietSection(dietTypes, toggleDietType),
                              const SizedBox(height: 24),

                              // Show More Filters Button (only when collapsed)
                              if (!showMoreFilters.value)
                                _buildShowMoreButton(showMoreFilters),

                              // Premium Filters (shown when expanded)
                              if (showMoreFilters.value) ...[
                                const SizedBox(height: 8),
                                _buildPremiumFiltersSection(
                                  minPhotos: minPhotos,
                                  hasBio: hasBio,
                                  onlyOnlineUsers: onlyOnlineUsers,
                                  onlyVerifiedProfiles: onlyVerifiedProfiles,
                                  markChange: markChange,
                                ),
                              ],

                              const SizedBox(height: 24),

                              // Apply Button
                              // _buildApplyButton(applyFilters),
                              SizedBox(
                                height:
                                    MediaQuery.of(context).padding.bottom + 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Close Button (positioned outside sheet)
              Positioned(
                right: 3,
                bottom: currentHeight - 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kSecondaryPurple,
                      borderRadius: BorderRadius.circular(15.56),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ValueNotifier<bool> showMoreFilters,
    ValueNotifier<RangeValues> ageRange,
    ValueNotifier<double> maxDistance,
    ValueNotifier<bool> showAllPeople,
    ValueNotifier<Set<String>> relationTypes,
    ValueNotifier<double> height,
    ValueNotifier<Set<String>> dietTypes,
    ValueNotifier<int> minPhotos,
    ValueNotifier<bool> hasBio,
    ValueNotifier<bool> onlyOnlineUsers,
    ValueNotifier<bool> onlyVerifiedProfiles,
    void Function() applyFilters,
    ValueNotifier<bool> hasChangesInCurrentSession,
    void Function() markChange,
  ) {
    /// Check if any filter is active
    // bool hasActiveFilters() {
    //   return ageRange.value != const RangeValues(18, 100) ||
    //       maxDistance.value < 150 ||
    //       !showAllPeople.value ||
    //       relationTypes.value.isNotEmpty ||
    //       height.value > 120 ||
    //       dietTypes.value.isNotEmpty ||
    //       minPhotos.value > 1 ||
    //       hasBio.value ||
    //       onlyOnlineUsers.value ||
    //       onlyVerifiedProfiles.value;
    // }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        children: [
          // Collapse button (only visible when expanded)
          if (showMoreFilters.value)
            GestureDetector(
              onTap: () {
                showMoreFilters.value = false;
              },
              child: Container(
                width: 41,
                height: 41,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.keyboard_double_arrow_down,
                  color: kSecondaryPurple,
                  size: 24,
                ),
              ),
            )
          else
            // Drag indicator when not expanded
            Container(
              width: 41,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9).withOpacity(0.5),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),

          // Title and Reset button
          Padding(
            padding: EdgeInsets.only(
              left: getProportionateScreenWidth(23),
              right: getProportionateScreenWidth(23),
              top: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Row(
                  children: [
                    // Apply Button - use hasChangesInCurrentSession instead of hasActiveFilters
                    _buildApplyButton(
                      applyFilters,
                      hasChangesInCurrentSession.value,
                    ),
                    SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        // Reset all filters to defaults
                        ageRange.value = const RangeValues(18, 100);
                        maxDistance.value = 150;
                        showAllPeople.value = true;
                        relationTypes.value = {};
                        height.value = 120;
                        dietTypes.value = {};
                        minPhotos.value = 1;
                        hasBio.value = false;
                        onlyOnlineUsers.value = false;
                        onlyVerifiedProfiles.value = false;
                        // Reset the session changes tracker
                        hasChangesInCurrentSession.value = false;
                        Navigator.of(context).pop(const HomeFilterState());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kSecondaryPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kSecondaryPurple, width: 1),
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: kSecondaryPurple,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeSection(
    ValueNotifier<RangeValues> ageRange,
    void Function() markChange,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Age',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            Text(
              '${ageRange.value.start.toInt()} to ${ageRange.value.end.toInt()} years',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF505050),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: _sliderTheme,
          child: RangeSlider(
            values: ageRange.value,
            min: 18,
            max: 100,
            divisions: 82,
            onChanged: (values) {
              ageRange.value = values;
              markChange();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceSection(
    ValueNotifier<double> maxDistance,
    ValueNotifier<bool> showAllPeople,
    void Function() markChange,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Distance',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            Text(
              '0 to ${maxDistance.value.toInt()}km',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF505050),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: _sliderTheme.copyWith(
            showValueIndicator: ShowValueIndicator.always,
          ),
          child: Slider(
            value: maxDistance.value,
            min: 1,
            max: 150,
            divisions: 149,
            label: '${maxDistance.value.toInt()}km',
            onChanged: (value) {
              maxDistance.value = value;
              markChange();
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Max 150km',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF656565),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Show people all over if not found',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: showAllPeople.value
                    ? const Color(0xFF505050)
                    : const Color(0xFF656565),
              ),
            ),
            const SizedBox(width: 6),
            _buildToggle(showAllPeople, markChange),
          ],
        ),
      ],
    );
  }

  Widget _buildRelationTypeSection(
    ValueNotifier<Set<String>> relationTypes,
    void Function(String) toggleRelationType,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Relation Type',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: kRelationTypes.map((type) {
            final isSelected = relationTypes.value.contains(type);
            return _buildChip(type, isSelected, () => toggleRelationType(type));
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHeightSection(
    ValueNotifier<double> height,
    void Function() markChange,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Height',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            Text(
              heightToFeetInches(height.value),
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF505050),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: _sliderTheme,
          child: Slider(
            value: height.value,
            min: 120, // ~4'0"
            max: 220, // ~7'3"
            divisions: 100,
            onChanged: (value) {
              height.value = value;
              markChange();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDietSection(
    ValueNotifier<Set<String>> dietTypes,
    void Function(String) toggleDietType,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Diet',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: kDietTypes.map((type) {
            final isSelected = dietTypes.value.contains(type);
            return _buildChip(type, isSelected, () => toggleDietType(type));
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildShowMoreButton(ValueNotifier<bool> showMoreFilters) {
    return Center(
      child: GestureDetector(
        onTap: () => showMoreFilters.value = true,
        child: Text(
          'Show more filters',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kSecondaryPurple,
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumFiltersSection({
    required ValueNotifier<int> minPhotos,
    required ValueNotifier<bool> hasBio,
    required ValueNotifier<bool> onlyOnlineUsers,
    required ValueNotifier<bool> onlyVerifiedProfiles,
    required void Function() markChange,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Minimum User Photos (only show if Top Picks is not active OR current user has ≥1 photo)
        // If Top Picks is active AND user has 0 photos, hide this option
        if (!isTopPicksActive || currentUserPhotoCount >= 1) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Minimum User photos',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              Text(
                '${minPhotos.value}',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF505050),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: _sliderTheme,
            child: Slider(
              value: minPhotos.value.toDouble(),
              min: 1,
              max: 6,
              divisions: 5,
              onChanged: (value) {
                minPhotos.value = value.toInt();
                markChange();
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'up to 6',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF656565),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Has Bio Toggle
        _buildToggleRow('Has Bio', hasBio, markChange),
        const SizedBox(height: 12),

        // Only Online Users Toggle
        _buildToggleRow('Only online users', onlyOnlineUsers, markChange),
        const SizedBox(height: 12),

        // Only Verified Profiles Toggle
        _buildToggleRow(
          'Only verified profiles',
          onlyVerifiedProfiles,
          markChange,
        ),
      ],
    );
  }

  Widget _buildToggleRow(
    String label,
    ValueNotifier<bool> value,
    void Function() markChange,
  ) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: value.value ? Colors.black : const Color(0xFF656565),
          ),
        ),
        const SizedBox(width: 6),
        _buildToggle(value, markChange),
      ],
    );
  }

  Widget _buildToggle(ValueNotifier<bool> value, void Function() markChange) {
    return GestureDetector(
      onTap: () {
        value.value = !value.value;
        markChange();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: value.value
              ? kSecondaryPurple
              : const Color(0xFF656565).withOpacity(0.3),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value.value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFBDBD).withOpacity(0.5)
              : const Color(0xFF797979).withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? kSecondaryPurple : const Color(0xFF7B7B7B),
          ),
        ),
      ),
    );
  }

  Widget _buildApplyButton(VoidCallback onTap, bool hasFilters) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 142,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: hasFilters
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFF3A2064),
                    Color(0xFF512A6B),
                    Color(0xFF693572),
                  ],
                )
              : null,
          color: !hasFilters ? const Color(0xFF656565).withAlpha(100) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Apply Filters',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  SliderThemeData get _sliderTheme => SliderThemeData(
    activeTrackColor: kSecondaryPurple,
    inactiveTrackColor: kSecondaryPurple.withOpacity(0.2),
    thumbColor: kSecondaryPurple,
    overlayColor: kSecondaryPurple.withOpacity(0.2),
    trackHeight: 4,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
  );
}
