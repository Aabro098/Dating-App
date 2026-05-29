import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';

// Custom clipper to create the notch at the top where the close button sits



class TopNotchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    double centerX = size.width / 2;
    
    // --- ADJUSTMENTS ---
    // 1. Reduced holeRadius from 38.0 to 33.0.
    // This matches the 63px width in your CSS almost exactly (31.5px radius + tiny buffer).
    double holeRadius = 33.0; 
    
    // 2. Reduced spread from 15.0 to 5.0.
    // This makes the curve start much later (closer to the button).
    double spread = 5.0; 
    
    // 3. Depth stays exactly as calculated from CSS.
    double notchDepth = 23.0; 

    path.moveTo(0, 0);

    // Draw straight line closer to center
    path.lineTo(centerX - holeRadius - spread, 0);

    // The Curve
    // We use the tighter radius to drop down quickly but smoothly
    path.cubicTo(
      centerX - holeRadius, 0,            // Control Point 1
      centerX - holeRadius, notchDepth,   // Control Point 2
      centerX, notchDepth,                // End Point (Bottom)
    );

    // Mirror Curve
    path.cubicTo(
      centerX + holeRadius, notchDepth,   // Control Point 3
      centerX + holeRadius, 0,            // Control Point 4
      centerX + holeRadius + spread, 0,   // End Point
    );

    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class CustomDatePicker extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const CustomDatePicker({
    Key? key,
    this.initialDate,
    required this.firstDate,
    required this.lastDate,
  }) : super(key: key);

  @override
  State<CustomDatePicker> createState() => _CustomDatePickerState();

  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    return await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: CustomDatePicker(
            initialDate: initialDate,
            firstDate: firstDate ?? DateTime(1950),
            lastDate: lastDate ?? DateTime.now(),
          ),
        );
      },
    );
  }
}

class _CustomDatePickerState extends State<CustomDatePicker> {
  late DateTime _selectedDate;
  late int _currentMonth;
  late int _currentYear;
  bool _showMonthPicker = false;
  bool _showYearPicker = false;

  static const Color greyText = Color(0xFF808080);

  final List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _currentMonth = _selectedDate.month;
    _currentYear = _selectedDate.year;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main container with curved notch at top
          Container(
            width: screenWidth * 0.95,
            margin: EdgeInsets.only(top: getProportionateScreenHeight(32)),
            child: ClipPath(
              clipper: TopNotchClipper(),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  getProportionateScreenWidth(20),
                  getProportionateScreenHeight(40),
                  getProportionateScreenWidth(20),
                  getProportionateScreenHeight(20),
                ),
                decoration: BoxDecoration(
                  color: kBackgroundBG,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTitle(),
                    SizedBox(height: getProportionateScreenHeight(32)),
                    _buildMonthYearSelector(),
                    SizedBox(height: getProportionateScreenHeight(28)),
                    _buildCalendar(),
                    SizedBox(height: getProportionateScreenHeight(28)),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
          ),
          // Close button with background circle
          Positioned(top: -10, left: 0, right: 0, child: _buildHeader()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: getProportionateScreenWidth(63),
          height: getProportionateScreenHeight(63),
          decoration: const BoxDecoration(
            color: kSecondaryPurple,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close,
            color: Colors.white,
            size: getProportionateScreenWidth(32),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Select your date of birth',
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: getProportionateScreenWidth(22),
          fontWeight: FontWeight.w600,
          color: Colors.black,
          letterSpacing: -0.315,
        ),
      ),
    );
  }

  Widget _buildMonthYearSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(width: getProportionateScreenWidth(25)),
        // Month selector
        GestureDetector(
          onTap: () {
            setState(() {
              _showMonthPicker = !_showMonthPicker;
              _showYearPicker = false;
            });
          },
          child: Row(
            children: [
              Text(
                _monthNames[_currentMonth - 1],
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: getProportionateScreenWidth(26),
                  fontWeight: FontWeight.w600,
                  color: kSecondaryPurple,
                  letterSpacing: -0.315,
                ),
              ),
              SizedBox(width: getProportionateScreenWidth(4)),
              SvgPicture.asset(
                'assets/svg/arrow_down.svg',
                width: getProportionateScreenWidth(8),
                height: getProportionateScreenHeight(8),
              ),
            ],
          ),
        ),
        SizedBox(width: getProportionateScreenWidth(20)),
        // Year selector
        GestureDetector(
          onTap: () {
            setState(() {
              _showYearPicker = !_showYearPicker;
              _showMonthPicker = false;
            });
          },
          child: Row(
            children: [
              Text(
                _currentYear.toString(),
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: getProportionateScreenWidth(26),
                  fontWeight: FontWeight.w600,
                  color: kSecondaryPurple,
                ),
              ),
              SizedBox(width: getProportionateScreenWidth(4)),
              SvgPicture.asset(
                'assets/svg/arrow_down.svg',
                width: getProportionateScreenWidth(8),
                height: getProportionateScreenHeight(8),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar() {
    if (_showMonthPicker) {
      return _buildMonthPickerDropdown();
    } else if (_showYearPicker) {
      return _buildYearPickerDropdown();
    } else {
      return _buildCalendarGrid();
    }
  }

  Widget _buildMonthPickerDropdown() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ListView.builder(
        itemCount: _monthNames.length,
        itemBuilder: (context, index) {
          final isSelected = index + 1 == _currentMonth;
          return GestureDetector(
            onTap: () {
              setState(() {
                _currentMonth = index + 1;
                _showMonthPicker = false;
                // Update selectedDate with new month, preserving day if possible
                final daysInNewMonth = DateTime(_currentYear, _currentMonth + 1, 0).day;
                final newDay = _selectedDate.day > daysInNewMonth ? daysInNewMonth : _selectedDate.day;
                _selectedDate = DateTime(_currentYear, _currentMonth, newDay);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? kSecondaryPurple : Colors.white,
              ),
              child: Text(
                _monthNames[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildYearPickerDropdown() {
    final years = List.generate(
      widget.lastDate.year - widget.firstDate.year + 1,
      (index) => widget.firstDate.year + index,
    ).reversed.toList();

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ListView.builder(
        itemCount: years.length,
        itemBuilder: (context, index) {
          final year = years[index];
          final isSelected = year == _currentYear;
          return GestureDetector(
            onTap: () {
              setState(() {
                _currentYear = year;
                _showYearPicker = false;
                // Update selectedDate with new year, preserving day and month if possible
                final daysInMonth = DateTime(_currentYear, _currentMonth + 1, 0).day;
                final newDay = _selectedDate.day > daysInMonth ? daysInMonth : _selectedDate.day;
                _selectedDate = DateTime(_currentYear, _currentMonth, newDay);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? kSecondaryPurple : Colors.white,
              ),
              child: Text(
                year.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarGrid() {
    return Column(
      children: [
        // Day headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map(
                (day) => Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: getProportionateScreenWidth(12),
                      fontWeight: FontWeight.w400,
                      color: greyText.withOpacity(0.6),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        SizedBox(height: getProportionateScreenHeight(14)),
        // Calendar days
        _buildDaysGrid(),
      ],
    );
  }

  Widget _buildDaysGrid() {
    final firstDayOfMonth = DateTime(_currentYear, _currentMonth, 1);
    final lastDayOfMonth = DateTime(_currentYear, _currentMonth + 1, 0);
    final daysInMonth = lastDayOfMonth.day;

    // Get the weekday of the first day (1 = Monday, 7 = Sunday)
    int firstWeekday = firstDayOfMonth.weekday;

    // Calculate days from previous month
    final previousMonth = DateTime(_currentYear, _currentMonth, 0);
    final daysInPreviousMonth = previousMonth.day;
    final previousMonthStartDay = daysInPreviousMonth - firstWeekday + 2;

    List<Widget> dayWidgets = [];

    // Add previous month days (greyed out)
    for (int i = previousMonthStartDay; i <= daysInPreviousMonth; i++) {
      dayWidgets.add(_buildDayCell(i, isCurrentMonth: false));
    }

    // Add current month days
    for (int day = 1; day <= daysInMonth; day++) {
      dayWidgets.add(_buildDayCell(day, isCurrentMonth: true));
    }

    // Add next month days to fill the grid
    int remainingCells = 35 - dayWidgets.length;
    if (remainingCells < 7) remainingCells += 7;

    for (int i = 1; i <= remainingCells; i++) {
      dayWidgets.add(_buildDayCell(i, isCurrentMonth: false));
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: dayWidgets,
    );
  }

  Widget _buildDayCell(int day, {required bool isCurrentMonth}) {
    final isSelected =
        isCurrentMonth &&
        day == _selectedDate.day &&
        _currentMonth == _selectedDate.month &&
        _currentYear == _selectedDate.year;

    return GestureDetector(
      onTap: isCurrentMonth
          ? () {
              setState(() {
                _selectedDate = DateTime(_currentYear, _currentMonth, day);
              });
            }
          : null,
      child: Container(
        margin: EdgeInsets.all(getProportionateScreenWidth(2)),
        decoration: BoxDecoration(
          color: isSelected ? kSecondaryPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(9.4),
        ),
        child: Center(
          child: Text(
            day.toString(),
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: getProportionateScreenWidth(16),
              fontWeight: FontWeight.w400,
              color: isSelected
                  ? Colors.white
                  : isCurrentMonth
                  ? Colors.black
                  : greyText,
              letterSpacing: -0.315,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop(_selectedDate);
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: getProportionateScreenHeight(15),
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [kPrimaryPurple, kTertiaryPink],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            'Save',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w600,
              fontSize: getProportionateScreenWidth(20),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
