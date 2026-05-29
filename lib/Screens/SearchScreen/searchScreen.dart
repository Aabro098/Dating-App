import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:viora/Screens/SearchScreen/components/searchedCard.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/components/outLineButton.dart';
import 'package:viora/constants.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:viora/size_config.dart';
import 'package:flutter/material.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../Services/Global.dart';

// --- BUSINESS LOGIC (stateless, reusable) ---

// Returns the opposite gender string
String getTargetGender(String userGender) =>
    userGender == "Female" ? "Male" : "Female";

// Query Helper: returns a Firestore query based on age and gender criteria
Query<Map<String, dynamic>> buildSearchQuery({
  required String targetGender,
  required int startAge,
  required int endAge,
}) {
  return FirebaseFirestore.instance
      .collection('Users')
      .where("gender", isEqualTo: targetGender)
      .where("age", isGreaterThanOrEqualTo: startAge)
      .where("age", isLessThanOrEqualTo: endAge)
      .orderBy("age")
      .orderBy('joiningDate', descending: true)
      .where("isDisabled", isEqualTo: false);
}

// --- CUSTOM HOOK: encapsulates search state & logic ---

class SearchParams {
  final int startAge;
  final int endAge;
  final bool searched;
  final void Function(int) setStartAge;
  final void Function(int) setEndAge;
  final VoidCallback setSearched;
  final VoidCallback resetSearched;
  SearchParams({
    required this.startAge,
    required this.endAge,
    required this.searched,
    required this.setStartAge,
    required this.setEndAge,
    required this.setSearched,
    required this.resetSearched,
  });
}

SearchParams useSearchParams() {
  final startAge = useState(18);
  final endAge = useState(18);
  final searched = useState(false);

  void setStart(int value) {
    startAge.value = value;
    endAge.value = value > endAge.value ? value : endAge.value;
  }

  return SearchParams(
    startAge: startAge.value,
    endAge: endAge.value,
    searched: searched.value,
    setStartAge: setStart,
    setEndAge: (v) => endAge.value = v,
    setSearched: () => searched.value = true,
    resetSearched: () => searched.value = false,
  );
}

// --- HOOKWIDGET: glue logic only for UI, hooks, business, backend ---

class SearchScreen extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final search = useSearchParams();
    final globals = Globals.of(context);

    final userGender = globals.userProvider.userDetails.gender;
    final targetGender = getTargetGender(userGender!);

    // Only build UI using Hook state, business, and query helpers
    if (!search.searched) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: getProportionateScreenHeight(20)),
          Text(
            "Age Range",
            style: TextStyle(fontSize: getProportionateScreenWidth(22)),
          ),
          Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              NumberPicker(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black26),
                ),
                haptics: true,
                value: search.startAge,
                minValue: 18,
                maxValue: 100,
                onChanged: (value) => search.setStartAge(value),
              ),
              Text(
                "To",
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(18),
                  color: kSecondaryColor,
                ),
              ),
              NumberPicker(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black26),
                ),
                value: search.endAge,
                haptics: true,
                minValue: search.startAge,
                maxValue: 100,
                onChanged: (value) => search.setEndAge(value),
              ),
            ],
          ),
          Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: search.setSearched,
              child: OutlineBtn(btnText: "SEARCH"),
            ),
          ),
          Spacer(),
        ],
      );
    } else {
      final query = buildSearchQuery(
        targetGender: targetGender,
        startAge: search.startAge,
        endAge: search.endAge,
      );
      return Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: getProportionateScreenHeight(5),
              vertical: getProportionateScreenHeight(10),
            ),
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text(
                    "Searched results",
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(18),
                      color: Colors.white,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: search.resetSearched,
                  child: Container(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: getProportionateScreenWidth(24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: FirestoreListView(
          query: query,
          itemBuilder: (context, documentSnapshots) {
            final data = documentSnapshots.data() as Map<String, dynamic>;
            return SearchedCard(user: UserDetails.fromJson(data));
          },
          padding: EdgeInsets.all(getProportionateScreenWidth(5)),
          emptyBuilder: (context) => Center(child: Text("No User Found")),
          loadingBuilder: (context) =>
              Center(child: CircularProgressIndicator()),
        ),
      );
    }
  }
}

/*
----------------------------------------------
Explanation: Hooks, Logic Separation & Benefits
----------------------------------------------
- All mutable state (startAge, endAge, searched) is managed by the custom hook `useSearchParams`, making local UI state logic testable and self-contained.
- Business logic (gender selection and Firestore query building) is in stateless helper functions and not within the widget tree.
- Backend/database querying is isolated to helper functions (`buildSearchQuery`).
- The widget does not contain business or backend logic, only invokes hooks, business, and repository functions, and glues them to UI.
- This results in a modular, maintainable, and highly testable architecture per Flutter and hooks best practices[web:1][web:2][web:3][web:4][web:5][web:6][web:8].
*/
