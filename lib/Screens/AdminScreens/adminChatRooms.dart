import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:viora/Screens/AdminScreens/supportMesageScreen.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/SupportModels.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:viora/utils/constatnts/colors.dart';
import 'package:viora/utils/helpers/admin_support_helper.dart';
import 'package:viora/utils/helpers/image_helper.dart';

import '../../constants.dart';
import '../../size_config.dart';

class AdminChatRooms extends StatefulWidget {
  static String routeName = "/adminChatRooms";

  const AdminChatRooms({super.key});

  @override
  AdminChatRoomsState createState() => AdminChatRoomsState();
}

class AdminChatRoomsState extends State<AdminChatRooms> {
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  List<String> _selectedCategoryIds = [];
  List<String> _selectedStatusIds = [];

  bool isLoading = true;

  late Query<Map<String, dynamic>> usersQuery;
  List<String> categoryIds = [];

  @override
  void initState() {
    super.initState();
    getCategoryIds();
    _updateQuery();
    isLoading = false;
  }

  void _updateQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('SupportChatRooms')
        .where("users", arrayContains: "support");

    if (_filterStartDate != null) {
      query = query.where(
        'lastMessageDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_filterStartDate!),
      );
    }

    if (_filterEndDate != null) {
      query = query.where(
        'lastMessageDate',
        isLessThanOrEqualTo: Timestamp.fromDate(_filterEndDate!),
      );
    }

    if (_selectedStatusIds.isNotEmpty) {
      // If only one status selected use isEqualTo, otherwise use whereIn
      if (_selectedStatusIds.length == 1) {
        query = query.where('status', isEqualTo: _selectedStatusIds.first);
      } else {
        query = query.where('status', whereIn: _selectedStatusIds);
      }
    }

    query = query.orderBy('lastMessageDate', descending: true);

    setState(() {
      usersQuery = query;
    });
  }

  Future<void> getCategoryIds() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('AppConfig')
          .doc('SupportConfig')
          .get();

      final categories = SupportFaqModel.fromFirestore(doc).categories;
      categoryIds = categories.map((cat) => cat.id).toList();
    } catch (e) {
      debugPrint('[AdminChatRooms] Error fetching categories: $e');
    }
  }

  void _showDateFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _FilterBottomSheet(
        currentStartDate: _filterStartDate,
        currentEndDate: _filterEndDate,
        availableCategoryIds: categoryIds,
        selectedCategoryIds: _selectedCategoryIds,
        selectedStatusIds: _selectedStatusIds,
        onFilter: (startDate, endDate, selectedCategories, selectedStatuses) {
          if (mounted) {
            setState(() {
              _filterStartDate = startDate;
              _filterEndDate = endDate;
              _selectedCategoryIds = selectedCategories;
              _selectedStatusIds = selectedStatuses;
            });
          }
          _updateQuery();
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? Center(
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          )
        : Scaffold(
            appBar: AppBar(
              backgroundColor: kPrimaryColor,
              leading: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                },
                child: Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: getProportionateScreenWidth(24),
                ),
              ),
              title: Text(
                "Support Chats",
                style: TextStyle(color: Colors.white),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.filter_list, color: Colors.white),
                  onPressed: _showDateFilterBottomSheet,
                  tooltip: 'Filter by date',
                ),
              ],
            ),
            body: FirestoreListView<Map<String, dynamic>>(
              query: usersQuery,
              itemBuilder: (context, snapshot) {
                Map<String, dynamic> data = snapshot.data();

                // Check if message is empty
                if (data["lastMessage"] == "") {
                  return SizedBox();
                }

                // Client-side category filtering
                if (_selectedCategoryIds.isNotEmpty) {
                  final chatRoom = ChatRoom.fromJson(data);
                  final chatCategories = chatRoom.categoryId ?? [];

                  // Check if chat room has at least one matching category
                  final hasMatchingCategory = _selectedCategoryIds.any(
                    (selectedCat) => chatCategories.contains(selectedCat),
                  );

                  if (!hasMatchingCategory) {
                    return SizedBox();
                  }
                }

                // Client-side status filtering as a safety-net (query should already filter)
                if (_selectedStatusIds.isNotEmpty) {
                  final chatRoom = ChatRoom.fromJson(data);
                  final roomStatus = chatRoom.status ?? '';
                  final matchesStatus = _selectedStatusIds.any(
                    (s) => s == roomStatus,
                  );
                  if (!matchesStatus) {
                    return SizedBox();
                  }
                }

                return AdminChatCard(chatRoom: ChatRoom.fromJson(data));
              },

              padding: EdgeInsets.all(getProportionateScreenWidth(5)),
              emptyBuilder: (context) {
                return Center(child: Text("Start chatting with someone"));
              },

              fetchingIndicatorBuilder: (context) =>
                  Center(child: CircularProgressIndicator()),
              loadingBuilder: (context) =>
                  Center(child: CircularProgressIndicator()),
            ),
          );
  }
}

class AdminChatCard extends StatefulWidget {
  AdminChatCard({super.key, required this.chatRoom});

  ChatRoom chatRoom;

  @override
  AdminChatCardState createState() => AdminChatCardState();
}

class AdminChatCardState extends State<AdminChatCard> {
  @override
  void initState() {
    super.initState();
    _isLoading = true;
    getUser();
  }

  UserDetails? _user;
  late bool _isLoading;

  Future<void> getUser() async {
    try {
      widget.chatRoom.users.remove("support");

      // Validate that users list is not empty
      if (widget.chatRoom.users.isEmpty) {
        debugPrint('[AdminChatCard] No users in chat room');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("Users");

      collectionReference
          .doc(widget.chatRoom.users[0])
          .get()
          .then((event) {
            // Null-safe check: ensure document exists and has data
            final data = event.data();
            if (data == null) {
              debugPrint(
                '[AdminChatCard] User document not found: ${widget.chatRoom.users[0]}',
              );
              setState(() {
                _isLoading = false;
              });
              return;
            }

            try {
              _user = UserDetails.fromJson(data as Map<String, dynamic>);
              setState(() {
                _isLoading = false;
              });
            } catch (e) {
              debugPrint('[AdminChatCard] Error parsing user data: $e');
              setState(() {
                _isLoading = false;
              });
            }
          })
          .catchError((error) {
            debugPrint('[AdminChatCard] Error fetching user: $error');
            setState(() {
              _isLoading = false;
            });
          });

      setState(() {});
    } catch (e) {
      debugPrint('[AdminChatCard] Unexpected error in getUser: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Return nothing if still loading or user not found
    if (_isLoading || _user == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () {
        PersistentNavBarNavigator.pushNewScreen(
          context,
          screen: SupportMessageScreen(uId: _user!.uid),
          withNavBar: false, // OPTIONAL VALUE. True by default.
          pageTransitionAnimation: PageTransitionAnimation.cupertino,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kDefaultPadding,
          vertical: kDefaultPadding * 0.75,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  child: ReactiveProfileImage(
                    imagePath: _user!.images!.isEmpty ? '' : _user!.images![0],
                    gender: _user!.gender ?? "male",
                    width: 50,
                    height: 50,
                  ),
                  // child: CachedNetworkImage(
                  //   imageUrl: _user!.images!.isEmpty
                  //       ? _user!.gender == "Male"
                  //             ? AppConfigService.maleImageUrl
                  //             : AppConfigService.femaleImageUrl
                  //       : _user!.images![0],
                  //   width: 50,
                  //   height: 50,
                  // ),
                ),
                if (_user!.isOnline == true)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 16,
                      width: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kDefaultPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _user!.name ?? 'name',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Opacity(
                      opacity: 0.64,
                      child: Text(
                        widget.chatRoom.lastMessage ==
                                "vioraa.firebasestorage.app"
                            ? "Image"
                            : widget.chatRoom.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.chatRoom.status != null
                            ? AdminSupportHelper()
                                  .color(widget.chatRoom.status ?? "no-status")
                                  .withAlpha(72)
                            : AppColors.lavendar.withAlpha(72),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.chatRoom.status != null
                            ? AdminSupportHelper().status(
                                widget.chatRoom.status ?? "no-status",
                              )
                            : "No status",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Opacity(
              opacity: 0.64,
              child: Text(
                timeago.format(
                  DateTime.now().subtract(
                    DateTime.now().difference(widget.chatRoom.lastMessageDate),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  final Function(DateTime?, DateTime?, List<String>, List<String>) onFilter;
  final DateTime? currentStartDate;
  final DateTime? currentEndDate;
  final List<String> availableCategoryIds;
  final List<String> selectedCategoryIds;
  final List<String> selectedStatusIds;

  const _FilterBottomSheet({
    required this.onFilter,
    this.currentStartDate,
    this.currentEndDate,
    required this.availableCategoryIds,
    required this.selectedCategoryIds,
    this.selectedStatusIds = const [],
  });

  @override
  _FilterBottomSheetState createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  DateTime? _tempStartDate;
  DateTime? _tempEndDate;
  String? _selectedFilterType; // 'past7', 'past30', 'custom', 'clear'
  late List<String> _tempSelectedCategoryIds;
  late List<String> _tempSelectedStatusIds;
  final List<String> _availableStatuses = [
    'new',
    'auto-replied',
    'resolved',
    'in-progress',
  ];

  @override
  void initState() {
    super.initState();
    _tempStartDate = widget.currentStartDate;
    _tempEndDate = widget.currentEndDate;
    _tempSelectedCategoryIds = List.from(widget.selectedCategoryIds);
    _tempSelectedStatusIds = List.from(widget.selectedStatusIds);
    _initializeFilterType();
  }

  void _initializeFilterType() {
    if (_tempStartDate == null || _tempEndDate == null) {
      _selectedFilterType = null;
      return;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final sevenDaysAgo = now.subtract(Duration(days: 7));
    final thirtyDaysAgo = now.subtract(Duration(days: 30));

    // Compare dates (ignoring time)
    final startDateOnly = DateTime(
      _tempStartDate!.year,
      _tempStartDate!.month,
      _tempStartDate!.day,
    );
    final endDateOnly = DateTime(
      _tempEndDate!.year,
      _tempEndDate!.month,
      _tempEndDate!.day,
    );
    final todayStartOnly = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day,
    );
    final todayEndOnly = DateTime(todayEnd.year, todayEnd.month, todayEnd.day);
    final sevenDaysAgoOnly = DateTime(
      sevenDaysAgo.year,
      sevenDaysAgo.month,
      sevenDaysAgo.day,
    );
    final thirtyDaysAgoOnly = DateTime(
      thirtyDaysAgo.year,
      thirtyDaysAgo.month,
      thirtyDaysAgo.day,
    );

    if (startDateOnly == todayStartOnly && endDateOnly == todayEndOnly) {
      _selectedFilterType = 'today';
    } else if (startDateOnly == sevenDaysAgoOnly) {
      _selectedFilterType = 'past7';
    } else if (startDateOnly == thirtyDaysAgoOnly) {
      _selectedFilterType = 'past30';
    } else {
      _selectedFilterType = 'custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filters',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _buildApplyButton(_hasChanges),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      if (mounted) {
                        setState(() {
                          _selectedFilterType = null;
                          _tempStartDate = null;
                          _tempEndDate = null;
                          _tempSelectedCategoryIds = [];
                          _tempSelectedStatusIds = [];
                        });
                        _applyFilter();
                      }
                    },
                    child: SafeArea(
                      child: SingleChildScrollView(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: kSecondaryPurple.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: kSecondaryPurple,
                              width: 1,
                            ),
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
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'By Date',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: [
              _FilterOption(
                title: 'Today',
                isSelected: _selectedFilterType == 'today',
                onTap: () {
                  if (!mounted || _selectedFilterType == 'today') {
                    return;
                  }
                  if (mounted) {
                    setState(() {
                      _selectedFilterType = 'today';
                      final now = DateTime.now();
                      _tempStartDate = DateTime(now.year, now.month, now.day);
                      _tempEndDate = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        23,
                        59,
                        59,
                        999,
                      );
                    });
                  }
                },
              ),
              _FilterOption(
                title: 'Past 7 Days',
                isSelected: _selectedFilterType == 'past7',
                onTap: () {
                  if (!mounted || _selectedFilterType == 'past7') {
                    return;
                  }
                  if (mounted) {
                    setState(() {
                      _selectedFilterType = 'past7';
                      _tempStartDate = DateTime.now().subtract(
                        Duration(days: 7),
                      );
                      _tempEndDate = DateTime.now();
                    });
                  }
                },
              ),
              _FilterOption(
                title: 'Past 30 Days',
                isSelected: _selectedFilterType == 'past30',
                onTap: () {
                  if (!mounted || _selectedFilterType == 'past30') {
                    return;
                  }
                  if (mounted) {
                    setState(() {
                      _selectedFilterType = 'past30';
                      _tempStartDate = DateTime.now().subtract(
                        Duration(days: 30),
                      );
                      _tempEndDate = DateTime.now();
                    });
                  }
                },
              ),
              // Custom range
              _FilterOption(
                title: 'Custom Range',
                isSelected: _selectedFilterType == 'custom',
                onTap: _showCustomDatePicker,
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'By Categories',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: widget.availableCategoryIds.map((categoryId) {
              final isSelected = _tempSelectedCategoryIds.contains(categoryId);
              return _FilterOption(
                title: categoryId
                    .split('_') // split words
                    .where((word) => word.isNotEmpty)
                    .map(
                      (word) =>
                          word[0].toUpperCase() +
                          word.substring(1).toLowerCase(),
                    )
                    .join(' '),
                isSelected: isSelected,
                onTap: () {
                  if (mounted) {
                    setState(() {
                      if (isSelected) {
                        _tempSelectedCategoryIds.remove(categoryId);
                      } else {
                        _tempSelectedCategoryIds.add(categoryId);
                      }
                    });
                  }
                },
              );
            }).toList(),
          ),
          SizedBox(height: 26),
          Text(
            'By Status',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: _availableStatuses.map((status) {
              final isSelected = _tempSelectedStatusIds.contains(status);
              return _FilterOption(
                title: status
                    .split('_')
                    .where((word) => word.isNotEmpty)
                    .map((word) => word[0].toUpperCase() + word.substring(1))
                    .join(' '),
                isSelected: isSelected,
                onTap: () {
                  if (mounted) {
                    setState(() {
                      if (isSelected) {
                        _tempSelectedStatusIds.remove(status);
                      } else {
                        _tempSelectedStatusIds.add(status);
                      }
                    });
                  }
                },
              );
            }).toList(),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildApplyButton(bool isEnabled) {
    return GestureDetector(
      onTap: _applyFilter,
      child: Container(
        width: 142,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isEnabled
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [kPrimaryPurple, kTertiaryPink],
                  stops: [0.0312, 2.9414],
                )
              : null,
          color: isEnabled ? null : Colors.grey.shade400,
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

  void _applyFilter() {
    if (_selectedFilterType == null &&
        _tempSelectedCategoryIds.isEmpty &&
        _tempSelectedStatusIds.isEmpty) {
      widget.onFilter(null, null, [], []);
    } else {
      widget.onFilter(
        _tempStartDate,
        _tempEndDate,
        _tempSelectedCategoryIds,
        _tempSelectedStatusIds,
      );
    }
  }

  bool get _hasChanges {
    final dateChanged =
        _tempStartDate != widget.currentStartDate ||
        _tempEndDate != widget.currentEndDate;
    final categoryChanged = !_sameCategorySelection(
      _tempSelectedCategoryIds,
      widget.selectedCategoryIds,
    );
    final statusChanged = !_sameCategorySelection(
      _tempSelectedStatusIds,
      widget.selectedStatusIds,
    );
    return dateChanged || categoryChanged || statusChanged;
  }

  bool _sameCategorySelection(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    final firstSet = first.toSet();
    final secondSet = second.toSet();
    if (firstSet.length != secondSet.length) return false;
    return firstSet.containsAll(secondSet);
  }

  void _showCustomDatePicker() async {
    final startDate = await showDatePicker(
      context: context,
      initialDate: _tempStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Select start date',
    );

    if (startDate == null) return;

    if (!mounted) return;
    final endDate = await showDatePicker(
      context: context,
      initialDate: _tempEndDate ?? DateTime.now(),
      firstDate: startDate,
      lastDate: DateTime.now(),
      helpText: 'Select end date',
    );

    if (endDate == null) return;

    if (mounted) {
      setState(() {
        _selectedFilterType = 'custom';
        _tempStartDate = startDate;
        _tempEndDate = endDate;
      });
    }
  }
}

class _FilterOption extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final bool isSelected;

  const _FilterOption({
    required this.title,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.purple.withAlpha(32)
              : AppColors.colorGrey.withAlpha(32),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.purple.withAlpha(100)
                : AppColors.colorGrey.withAlpha(100),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.purple : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
