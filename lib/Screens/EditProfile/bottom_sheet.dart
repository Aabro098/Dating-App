import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:viora/utils/constatnts/colors.dart';

// Static cache for work and education lists
class _ProfileListsCache {
  static final Map<String, List<String>> _cache = {};

  static List<String>? get(String key) => _cache[key];

  static void set(String key, List<String> value) {
    _cache[key] = value;
  }

  static bool has(String key) => _cache.containsKey(key);

  // static void clear() => _cache.clear();
}

class AppBottomSheet extends StatefulWidget {
  const AppBottomSheet({required this.isWork, super.key});

  final bool isWork;

  @override
  State<AppBottomSheet> createState() => _AppBottomSheetState();
}

class _AppBottomSheetState extends State<AppBottomSheet> {
  final TextEditingController searchController = TextEditingController();

  List<String> workList = [];
  List<String> educationList = [];

  List<String> filteredList = [];
  bool isLoading = false;

  List<String> get sourceList => widget.isWork ? workList : educationList;

  @override
  void initState() {
    super.initState();
    searchController.addListener(_filterList);
    _loadData();
  }

  Future<void> _loadData() async {
    final cacheKey = widget.isWork ? 'work' : 'education';

    // Check if data is already cached in memory
    if (_ProfileListsCache.has(cacheKey)) {
      final cached = _ProfileListsCache.get(cacheKey);
      if (mounted) {
        setState(() {
          if (widget.isWork) {
            workList = cached ?? [];
          } else {
            educationList = cached ?? [];
          }
          filteredList = List<String>.from(sourceList);
        });
      }
      return;
    }

    // If not cached, fetch from Firestore
    if (widget.isWork) {
      await _fetchWorkListFromFirestore();
    } else {
      await _fetchEducationListFromFirestore();
    }

    if (mounted) {
      setState(() {
        filteredList = List<String>.from(sourceList);
      });
    }
  }

  Future<void> _fetchWorkListFromFirestore() async {
    setState(() {
      isLoading = true;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('AppConfig')
          .doc('profile')
          .get();

      final data = doc.data();
      final dynamic works = data?['work'];

      if (works is List) {
        workList = works
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        workList = [];
      }

      // Store in memory cache
      _ProfileListsCache.set('work', workList);
    } catch (e) {
      workList = [];
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchEducationListFromFirestore() async {
    setState(() {
      isLoading = true;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('AppConfig')
          .doc('profile')
          .get();

      final data = doc.data();
      final dynamic education = data?['education'];

      if (education is List) {
        educationList = education
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        educationList = [];
      }

      // Store in memory cache
      _ProfileListsCache.set('education', educationList);
    } catch (e) {
      educationList = [];
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _filterList() {
    final query = searchController.text.trim().toLowerCase();

    if (!mounted) return;

    setState(() {
      filteredList = sourceList.where((item) {
        return item.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    searchController.removeListener(_filterList);
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select ${widget.isWork ? "Work" : "Education"}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.purple,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.isWork ? "work" : "education"}',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.colorGrey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.borderColor,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.borderColor,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.purple, width: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredList.isEmpty
                    ? Center(
                        child: Text(
                          'No ${widget.isWork ? "work" : "education"} found',
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: filteredList.length,
                        separatorBuilder: (_, _) => const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1),
                        ),
                        itemBuilder: (context, index) {
                          final item = filteredList[index];

                          return ListTile(
                            title: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context, item);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
