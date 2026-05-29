import 'package:flutter/material.dart';
import 'package:viora/size_config.dart';
import 'package:viora/utils/constatnts/colors.dart';

class CustomChipsChoice extends StatelessWidget {
  final String title;
  final List<String> options;
  final int? selectedValue;
  final Function(int) onChanged;
  final Color selectedColor;
  final Color unselectedColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;

  const CustomChipsChoice({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.selectedColor = AppColors.lightPink,
    this.unselectedColor = AppColors.greyShade,
    this.selectedTextColor = AppColors.purple,
    this.unselectedTextColor = AppColors.greyText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: getProportionateScreenHeight(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.purple,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: getProportionateScreenHeight(6)),
          Wrap(
            spacing: getProportionateScreenWidth(8),
            runSpacing: getProportionateScreenHeight(8),
            children: options.map((option) {
              final isSelected = selectedValue == options.indexOf(option);
              return GestureDetector(
                onTap: () => onChanged(options.indexOf(option)),
                child: Container(
                  padding: EdgeInsets.all(getProportionateScreenWidth(10)),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? selectedColor.withAlpha(92)
                        : unselectedColor.withAlpha(42),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      color: isSelected
                          ? selectedTextColor
                          : unselectedTextColor,
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class MultiChipsChoice extends StatefulWidget {
  final String title;
  final List<String> options;
  final Set<int> selectedValues;
  final ValueChanged<Set<int>> onChanged;

  final int initialVisibleCount;

  final Color selectedColor;
  final Color unselectedColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final bool? showCheckIcon;

  const MultiChipsChoice({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.initialVisibleCount = 15,
    this.selectedColor = AppColors.lightPink,
    this.unselectedColor = AppColors.greyShade,
    this.selectedTextColor = AppColors.purple,
    this.unselectedTextColor = AppColors.greyText,
    this.showCheckIcon = false,
  });

  @override
  State<MultiChipsChoice> createState() => _MultiChipsChoiceState();
}

class _MultiChipsChoiceState extends State<MultiChipsChoice> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasOverflow = widget.options.length > widget.initialVisibleCount;

    final visibleOptions = _expanded
        ? widget.options
        : widget.options.take(widget.initialVisibleCount).toList();

    return Padding(
      padding: EdgeInsets.only(top: getProportionateScreenHeight(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: AppColors.purple,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          /// Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(visibleOptions.length, (index) {
              final option = visibleOptions[index];
              final originalIndex = widget.options.indexOf(option); // safe here

              final isSelected = widget.selectedValues.contains(originalIndex);

              return GestureDetector(
                onTap: () {
                  final newSelection = Set<int>.from(widget.selectedValues);
                  if (isSelected) {
                    newSelection.remove(originalIndex);
                  } else {
                    newSelection.add(originalIndex);
                  }

                  widget.onChanged(newSelection);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? widget.selectedColor.withAlpha(92)
                        : widget.unselectedColor.withAlpha(42),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option,
                            style: TextStyle(
                              color: isSelected
                                  ? widget.selectedTextColor
                                  : widget.unselectedTextColor,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          if (widget.showCheckIcon == true) ...[
                            SizedBox(width: getProportionateScreenWidth(4)),
                            Icon(
                              isSelected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 16,
                              color: isSelected
                                  ? widget.selectedTextColor
                                  : widget.unselectedTextColor,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),

          /// Show More / Less
          if (hasOverflow)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: GestureDetector(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  }
                },
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    _expanded ? "Show Less" : "Show More",
                    style: TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
