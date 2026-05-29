import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:chips_choice/chips_choice.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/components/default_button.dart';
import 'package:viora/constants.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';
import 'package:viora/size_config.dart';

// Import your isolates helper

// Custom hooks for separated logic
import '../../Services/Global.dart';
import '../../Services/account_deletion_flow.dart';

class EditProfile extends HookWidget {
  static String routeName = "/editProfile";

  const EditProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);

    // Fetching user details using a custom hook.
    // This should read from prefs with parsing handled in an isolate.
    final userDetails = useValueListenable(globals.prefs.userDetails);

    // TextField Controllers managed with hooks – ensures disposal and persistent state.
    final nameController = useTextEditingController(
      text: userDetails?.name ?? '',
    );
    final stateController = useTextEditingController(
      text: userDetails?.state ?? '',
    );
    final cityController = useTextEditingController(
      text: userDetails?.city ?? '',
    );
    final ageController = useTextEditingController(
      text: userDetails?.age?.toString() ?? '',
    );
    final aboutController = useTextEditingController(
      text: userDetails?.about ?? '',
    );

    // UI State
    final sexualOrientation = useState(userDetails?.sexualOrientation ?? "");
    final maritalStatus = useState(userDetails?.maritalStatus ?? "");
    final relationTypes = useState<List<String>>(
      userDetails?.relTypes ?? <String>[],
    );
    final diet = useState(userDetails?.diet ?? "");
    final zodiac = useState(userDetails?.zodiac ?? "");
    final religion = useState(userDetails?.religion ?? "");
    final smoker = useState(userDetails?.smoker ?? "");
    final drinking = useState(userDetails?.drinking ?? "");
    final interests = useState<List<String>>(
      userDetails?.interests ?? <String>[],
    );

    // Errors state for form validation
    final errors = useState<List<String>>([]);
    final isDeletingAccount = useState(false);

    // Form key (reference through hook for proper use in widgets)
    final formKeyRef = useRef(GlobalKey<FormState>());

    // Field lists
    final orientation = [
      "Bisexual",
      "Gay",
      "Straight",
      "Lesbian",
      "Queer",
      "Asexual",
    ];
    final maritalStrings = ["Single", "Married", "Divorced", "Separated"];
    final relationStrings = [
      "Excitement",
      "Long Term",
      "Open to anything",
      "Short Term",
      "Undecided",
      "Virtual",
      "No String attached",
    ];
    final dietStrings = ["Vegetarian", "Non-vegetarian", "Vegan", "Other"];
    final zodiacStrings = [
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
    final religionStrings = [
      "Hindu",
      "Muslim",
      "Christian",
      "Sikh",
      "Buddhist",
      "Jain",
      "Atheist",
      "Other",
    ];
    final smokerStrings = ["Yes", "No", "Occasionally"];
    final drinkingStrings = ["Yes", "No", "Socially"];
    final interestStrings = [
      "Travel",
      "Music",
      "Sports",
      "Reading",
      "Movies",
      "Cooking",
      "Fitness",
      "Art",
      "Photography",
      "Gaming",
      "Dancing",
      "Yoga",
    ];

    // Memoize heavy operations if needed
    // Example: Deep parse user details if needed, using isolates
    // final parsedUserDetails = useMemoized(() async {
    //   if (userDetails == null) return null;
    //   return await parseUserDetailsInIsolate(userDetails.toJsonString());
    // }, [userDetails]);

    // Validation hook to encapsulate form validation logic

    final validateForm = useCallback(() {
      errors.value = [];
      if (nameController.text.isEmpty)
        errors.value = [...errors.value, "Username required"];
      if (stateController.text.isEmpty)
        errors.value = [...errors.value, "State required"];
      if (cityController.text.isEmpty)
        errors.value = [...errors.value, "City required"];
      if (ageController.text.isEmpty)
        errors.value = [...errors.value, "Age required"];
      return errors.value.isEmpty;
    }, [nameController, stateController, cityController, ageController]);

    // Apply changes handler (memoized for efficiency)
    final handleApplyChanges = useCallback(
      () async {
        final isValid = validateForm();
        if (isValid) {
          // Efficient backend/state update, pure business logic functions
          UserDetails prevUserDetails = userDetails!;
          prevUserDetails.name = nameController.text;
          prevUserDetails.age =
              int.tryParse(ageController.text) ?? userDetails.age;
          prevUserDetails.city = cityController.text;
          prevUserDetails.state = stateController.text;
          debugPrint(
            "vinay i called prefs set from handleApplyChanges->editProfile",
          );

          globals.prefs.userDetails.set(prevUserDetails);
          DatabaseService.updateField({
            "name": nameController.text,
            "age": int.tryParse(ageController.text) ?? userDetails.age,
            "city": cityController.text,
            "state": stateController.text,
            "maritalStatus": maritalStatus.value,
            "relTypes": relationTypes.value,
            "sexualOrientation": sexualOrientation.value,
            "about": aboutController.text,
            "diet": diet.value,
            "zodiac": zodiac.value,
            "religion": religion.value,
            "smoker": smoker.value,
            "drinking": drinking.value,
            "interests": interests.value,
          });
          prevUserDetails.maritalStatus = maritalStatus.value;
          prevUserDetails.relTypes = relationTypes.value;
          // prevUserDetails.sexualOrientation = sexualOrientation.value;
          prevUserDetails.about = aboutController.text;
          prevUserDetails.diet = diet.value;
          prevUserDetails.zodiac = zodiac.value;
          prevUserDetails.religion = religion.value;
          prevUserDetails.smoker = smoker.value;
          prevUserDetails.drinking = drinking.value;
          prevUserDetails.interests = interests.value;
          globals.prefs.userDetails.set(prevUserDetails);
          Navigator.pop(context);
          showSimpleNotification(
            Text("Profile updated Successfully"),
            leading: Icon(Icons.done),
            position: NotificationPosition.bottom,
            background: Colors.green,
            duration: Duration(seconds: 2),
            slideDismiss: true,
          );
        }
      },
      [
        validateForm,
        nameController,
        stateController,
        cityController,
        ageController,
      ],
    );

    void handleDeleteProfile() {
      if (isDeletingAccount.value) return;
      // showAccountDeletionConfirmation(
      //   context,
      //   isDeletingAccount,
      //   globals,
      //   deletionMethod: 'edit_profile',
      // );
    }

    // UI Layer: Only rendering logic, NO backend/data transformations.
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child: SafeArea(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                Spacer(),
                Text(
                  "Edit Profile",
                  style: TextStyle(fontSize: 20, color: Colors.white),
                ),
                Spacer(),
                GestureDetector(
                  onTap: handleDeleteProfile,
                  child: Icon(Icons.delete, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: formKeyRef.value,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildUserNameFormField(
                  nameController,
                  errors,
                  addError: (err) {
                    if (!errors.value.contains(err)) {
                      errors.value = [...errors.value, err];
                    }
                  },
                ),
                SizedBox(height: 10),
                buildStateFormField(
                  stateController,
                  errors,
                  addError: (err) {
                    if (!errors.value.contains(err)) {
                      errors.value = [...errors.value, err];
                    }
                  },
                  context: context,
                ),
                SizedBox(height: 10),
                buildCityFormField(
                  cityController,
                  errors,
                  addError: (err) {
                    if (!errors.value.contains(err)) {
                      errors.value = [...errors.value, err];
                    }
                  },
                  context: context,
                ),
                SizedBox(height: 10),
                buildAgeFormField(
                  ageController,
                  errors,
                  addError: (err) {
                    if (!errors.value.contains(err)) {
                      errors.value = [...errors.value, err];
                    }
                  },
                ),
                DefaultButton(text: "Apply Changes", press: handleApplyChanges),
                SizedBox(height: 10),
                Text("Sexual Orientation"),
                // ChipsChoice.single(
                //   choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                //   value: orientation.indexOf(sexualOrientation.value),
                //   onChanged: (val) {
                //     UserDetails prevUserDetails = userDetails!;
                //     prevUserDetails.sexualOrientation = orientation[val];
                //     debugPrint(
                //       "vinay i called prefs set from Sexual Orientation->editProfile",
                //     );
                //     globals.prefs.userDetails.set(prevUserDetails);
                //     sexualOrientation.value = orientation[val];
                //     DatabaseService.updateField({
                //       "sexualOrientation": orientation[val],
                //     });
                //   },
                //   choiceItems: C2Choice.listFrom(
                //     source: orientation,
                //     value: (i, v) => i,
                //     label: (i, v) => v,
                //   ),
                // ),
                Text("Marital Status"),
                ChipsChoice.single(
                  choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                  value: maritalStrings.indexOf(maritalStatus.value),
                  onChanged: (val) {
                    maritalStatus.value = maritalStrings[val];
                    UserDetails prevUserDetails = userDetails!;
                    prevUserDetails.maritalStatus = maritalStrings[val];
                    debugPrint(
                      "vinay i called prefs set from Marital Status->editProfile",
                    );
                    globals.prefs.userDetails.set(prevUserDetails);
                    DatabaseService.updateField({
                      "maritalStatus": maritalStrings[val],
                    });
                  },
                  choiceItems: C2Choice.listFrom(
                    source: maritalStrings,
                    value: (i, v) => i,
                    label: (i, v) => v,
                  ),
                ),
                Text("Types of Relationship looking for"),
                Wrap(
                  children: relationStrings
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: GestureDetector(
                            onTap: () {
                              if (relationTypes.value.contains(i)) {
                                debugPrint(
                                  "Updating rel typess removed ${FieldValue.arrayRemove([i]).toString()}",
                                );
                                DatabaseService.updateField({
                                  "relTypes": FieldValue.arrayRemove([i]),
                                });

                                relationTypes.value = relationTypes.value
                                    .where((type) => type != i)
                                    .toList();
                              } else {
                                debugPrint(
                                  "Updating rel typess added ${FieldValue.arrayUnion([i]).toString()}",
                                );

                                DatabaseService.updateField({
                                  "relTypes": FieldValue.arrayUnion([i]),
                                });
                                relationTypes.value = [
                                  ...relationTypes.value,
                                  i,
                                ];
                                UserDetails prevUserDetails = userDetails!;
                                prevUserDetails.relTypes = relationTypes.value;
                                debugPrint(
                                  "vinay i called prefs set from rel types->editProfile",
                                );
                                globals.prefs.userDetails.set(prevUserDetails);
                              }
                            },
                            child: Chip(
                              backgroundColor: relationTypes.value.contains(i)
                                  ? kPrimaryColor
                                  : kSecondaryColor,
                              label: Text(
                                i,
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                SizedBox(height: 20),
                Text(
                  "Top Picks Profile",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
                Text(
                  "Complete these fields to improve your Top Picks matches",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SizedBox(height: 10),
                buildAboutFormField(aboutController),
                SizedBox(height: 10),
                Text("Diet"),
                ChipsChoice.single(
                  choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                  value: diet.value.isEmpty
                      ? -1
                      : dietStrings.indexOf(diet.value),
                  onChanged: (val) {
                    diet.value = val >= 0 ? dietStrings[val] : "";
                    UserDetails prevUserDetails = userDetails!;
                    prevUserDetails.diet = diet.value;
                    globals.prefs.userDetails.set(prevUserDetails);
                    DatabaseService.updateField({"diet": diet.value});
                  },
                  choiceItems: C2Choice.listFrom(
                    source: dietStrings,
                    value: (i, v) => i,
                    label: (i, v) => v,
                  ),
                ),
                Text("Zodiac Sign"),
                ChipsChoice.single(
                  choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                  value: zodiac.value.isEmpty
                      ? -1
                      : zodiacStrings.indexOf(zodiac.value),
                  onChanged: (val) {
                    zodiac.value = val >= 0 ? zodiacStrings[val] : "";
                    UserDetails prevUserDetails = userDetails!;
                    prevUserDetails.zodiac = zodiac.value;
                    globals.prefs.userDetails.set(prevUserDetails);
                    DatabaseService.updateField({"zodiac": zodiac.value});
                  },
                  choiceItems: C2Choice.listFrom(
                    source: zodiacStrings,
                    value: (i, v) => i,
                    label: (i, v) => v,
                  ),
                ),
                Text("Religion"),
                ChipsChoice.single(
                  choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                  value: religion.value.isEmpty
                      ? -1
                      : religionStrings.indexOf(religion.value),
                  onChanged: (val) {
                    religion.value = val >= 0 ? religionStrings[val] : "";
                    UserDetails prevUserDetails = userDetails!;
                    prevUserDetails.religion = religion.value;
                    globals.prefs.userDetails.set(prevUserDetails);
                    DatabaseService.updateField({"religion": religion.value});
                  },
                  choiceItems: C2Choice.listFrom(
                    source: religionStrings,
                    value: (i, v) => i,
                    label: (i, v) => v,
                  ),
                ),
                Text("Smoker"),
                ChipsChoice.single(
                  choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                  value: smoker.value.isEmpty
                      ? -1
                      : smokerStrings.indexOf(smoker.value),
                  onChanged: (val) {
                    smoker.value = val >= 0 ? smokerStrings[val] : "";
                    UserDetails prevUserDetails = userDetails!;
                    prevUserDetails.smoker = smoker.value;
                    globals.prefs.userDetails.set(prevUserDetails);
                    DatabaseService.updateField({"smoker": smoker.value});
                  },
                  choiceItems: C2Choice.listFrom(
                    source: smokerStrings,
                    value: (i, v) => i,
                    label: (i, v) => v,
                  ),
                ),
                Text("Drinking"),
                ChipsChoice.single(
                  choiceStyle: C2ChipStyle(checkmarkColor: kPrimaryColor),
                  value: drinking.value.isEmpty
                      ? -1
                      : drinkingStrings.indexOf(drinking.value),
                  onChanged: (val) {
                    drinking.value = val >= 0 ? drinkingStrings[val] : "";
                    UserDetails prevUserDetails = userDetails!;
                    prevUserDetails.drinking = drinking.value;
                    globals.prefs.userDetails.set(prevUserDetails);
                    DatabaseService.updateField({"drinking": drinking.value});
                  },
                  choiceItems: C2Choice.listFrom(
                    source: drinkingStrings,
                    value: (i, v) => i,
                    label: (i, v) => v,
                  ),
                ),
                Text("Interests (Select multiple)"),
                Wrap(
                  children: interestStrings
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: GestureDetector(
                            onTap: () {
                              if (interests.value.contains(i)) {
                                DatabaseService.updateField({
                                  "interests": FieldValue.arrayRemove([i]),
                                });
                                interests.value = interests.value
                                    .where((interest) => interest != i)
                                    .toList();
                              } else {
                                DatabaseService.updateField({
                                  "interests": FieldValue.arrayUnion([i]),
                                });
                                interests.value = [...interests.value, i];
                                UserDetails prevUserDetails = userDetails!;
                                prevUserDetails.interests = interests.value;
                                globals.prefs.userDetails.set(prevUserDetails);
                              }
                            },
                            child: Chip(
                              backgroundColor: interests.value.contains(i)
                                  ? kPrimaryColor
                                  : kSecondaryColor,
                              label: Text(
                                i,
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Username field
TextFormField buildUserNameFormField(
  TextEditingController controller,
  ValueNotifier<List<String>> errors, {
  required void Function(String) addError,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: TextInputType.name,
    validator: (value) {
      if (value == null || value.isEmpty) {
        addError("Username cannot be empty");
        return "";
      }
      return null;
    },
    decoration: InputDecoration(
      helperText: ' ',
      labelText: "Username",
      hintText: "Enter Username",
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: CustomSurffixIcon(iconData: Icons.person),
    ),
  );
}

// State field
TextFormField buildStateFormField(
  TextEditingController controller,
  ValueNotifier<List<String>> errors, {
  required void Function(String) addError,
  required BuildContext context,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: TextInputType.name,
    readOnly: true,
    onTap: () {
      try {
        showSimpleNotification(
          Text("Fetching Location"),
          background: Colors.green,
          duration: Duration(seconds: 5),
          position: NotificationPosition.top,
        );
        Provider.of<UserProvider>(context, listen: false).getIpandLoc(context);
      } catch (e) {
        showSimpleNotification(
          Text("Error Fetching Location, Try Again"),
          background: Colors.red,
          duration: Duration(seconds: 5),
          position: NotificationPosition.top,
        );
      } finally {
        showSimpleNotification(
          Text("Location Fetched"),
          background: Colors.green,
          duration: Duration(seconds: 5),
          position: NotificationPosition.top,
        );
      }
    },
    validator: (value) {
      if (value == null || value.isEmpty) {
        addError("State cannot be empty");
        return "";
      }
      return null;
    },
    decoration: InputDecoration(
      helperText: ' ',
      labelText: "State",
      hintText: "Enter State",
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: CustomSurffixIcon(iconData: Icons.pin_drop),
    ),
  );
}

// City field
TextFormField buildCityFormField(
  TextEditingController controller,
  ValueNotifier<List<String>> errors, {
  required void Function(String) addError,
  required BuildContext context,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: TextInputType.name,
    readOnly: true,
    onTap: () {
      try {
        showSimpleNotification(
          Text("Fetching Location"),
          background: Colors.green,
          duration: Duration(seconds: 5),
          position: NotificationPosition.top,
        );
        Provider.of<UserProvider>(context, listen: false).getIpandLoc(context);
      } catch (e) {
        showSimpleNotification(
          Text("Error Fetching Location, Try Again"),
          background: Colors.red,
          duration: Duration(seconds: 5),
          position: NotificationPosition.top,
        );
      } finally {
        showSimpleNotification(
          Text("Location Fetched"),
          background: Colors.green,
          duration: Duration(seconds: 5),
          position: NotificationPosition.top,
        );
      }
    },
    validator: (value) {
      if (value == null || value.isEmpty) {
        addError("City cannot be empty");
        return "";
      }
      return null;
    },
    decoration: InputDecoration(
      helperText: ' ',
      labelText: "City",
      hintText: "Enter City",
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: CustomSurffixIcon(iconData: Icons.pin_drop),
    ),
  );
}

// Age field
TextFormField buildAgeFormField(
  TextEditingController controller,
  ValueNotifier<List<String>> errors, {
  required void Function(String) addError,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    validator: (value) {
      if (value == null || value.isEmpty) {
        addError("Age cannot be empty");
        return "";
      }
      return null;
    },
    decoration: InputDecoration(
      helperText: ' ',
      labelText: "Age",
      hintText: "Enter Age",
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: CustomSurffixIcon(iconData: Icons.date_range),
    ),
  );
}

// About field
TextFormField buildAboutFormField(TextEditingController controller) {
  return TextFormField(
    controller: controller,
    keyboardType: TextInputType.multiline,
    maxLines: 3,
    maxLength: 500,
    decoration: InputDecoration(
      labelText: "About Me",
      hintText: "Tell something about yourself",
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: CustomSurffixIcon(iconData: Icons.info),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
