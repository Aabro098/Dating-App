import 'package:chips_choice/chips_choice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:viora/components/default_button.dart';
import 'package:overlay_support/overlay_support.dart';
import '../../constants.dart';
import '../../size_config.dart';

class EditBotProfile extends StatefulWidget {
  String botId;
  EditBotProfile({required this.botId});

  @override
  _EditBotProfileState createState() => _EditBotProfileState();
}

class _EditBotProfileState extends State<EditBotProfile> {
  final _formKey = GlobalKey<FormState>();
  C2ChipStyle choiceActiveStyle = new C2ChipStyle(
    checkmarkColor: kPrimaryColor,
  );
  late UserDetails user;

  late int sexualOrientation;

  late int maritalStatus;

  var orientation = [
    "Bisexual",
    "Gay",
    "Straight",
    "Lesbian",
    "Queer",
    "Asexual",
  ];
  var maritalStrings = ["Single", "Married", "Divorced", "Separated"];
  var relationStrings = [
    "Excitement",
    "Long Term",
    "Open to anything",
    "Short Term",
    "Undecided",
    "Virtual",
    "Purely sexual",
    "No String attached",
  ];

  // Top Picks Fields Options
  var dietStrings = ["Vegetarian", "Non-Vegetarian", "Vegan", "Eggetarian"];
  var zodiacStrings = [
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
  var religionStrings = [
    "Hindu",
    "Muslim",
    "Christian",
    "Sikh",
    "Buddhist",
    "Jain",
    "Atheist",
    "Other",
  ];
  var smokerStrings = ["Non-Smoker", "Occasional", "Regular"];
  var drinkingStrings = ["Non-Drinker", "Social", "Regular"];
  var interestStrings = [
    "Music",
    "Movies",
    "Travel",
    "Sports",
    "Fitness",
    "Gaming",
    "Reading",
    "Cooking",
    "Photography",
    "Art",
    "Dancing",
    "Technology",
  ];

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    isLoading = true;
    load();
  }

  late bool isLoading;

  CollectionReference collectionReference = FirebaseFirestore.instance
      .collection("Users");

  TextEditingController aboutCtr = TextEditingController();

  Future<void> load() async {
    collectionReference.doc(widget.botId).snapshots().listen((value) {
      user = UserDetails.fromJson(value.data() as Map<String, dynamic>);
      uNameCtr.text = user.name!;
      stateCtr.text = user.state!;
      cityCtr.text = user.city!;
      ageCtr.text = user.age.toString();
      aboutCtr.text = user.about ?? '';

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        child:
            /// Custom Navigation Drawer and Search Button
            SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: 57.6,
                        width: 57.6,
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9.6),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios,
                          color: Colors.white,
                          size: getProportionateScreenWidth(28),
                        ),
                      ),
                    ),
                    Spacer(flex: 1),
                    Text(
                      "Edit Bot Profile",
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(20),
                        color: Colors.white,
                      ),
                    ),
                    Spacer(flex: 2),
                  ],
                ),
              ),
            ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          buildUserNameFormField(),
                          SizedBox(height: getProportionateScreenHeight(10)),
                          buildStateFormField(),
                          SizedBox(height: getProportionateScreenHeight(10)),
                          buildCityFormField(),
                          SizedBox(height: getProportionateScreenHeight(10)),
                          buildAgeFormField(),
                          DefaultButton(
                            text: "Apply Changes",
                            press: () {
                              if (_formKey.currentState!.validate()) {
                                FocusScope.of(
                                  context,
                                ).requestFocus(FocusNode());

                                DatabaseService.updateUserField(widget.botId, {
                                  "name": uNameCtr.text,
                                  "age": int.parse(ageCtr.text),
                                  "city": cityCtr.text,
                                  "state": stateCtr.text,
                                });
                                //   toast("Profile updated Successfully");
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
                          ),
                          SizedBox(height: getProportionateScreenHeight(10)),
                        ],
                      ),
                    ),
                    Text("Sexual Orientation"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: orientation.indexOf(
                            (user.sexualOrientation as List?)?.firstOrNull ??
                                '',
                          ),
                          onChanged: (val) {
                            setState(() {
                              sexualOrientation = val;
                            });
                            DatabaseService.updateUserField(widget.botId, {
                              "sexualOrientation": orientation[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: orientation,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),
                    Text("Marital Status"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: maritalStrings.indexOf(
                            user.maritalStatus ?? '',
                          ),
                          onChanged: (val) {
                            setState(() {
                              maritalStatus = val;
                            });
                            print(maritalStrings[val]);
                            DatabaseService.updateUserField(widget.botId, {
                              "maritalStatus": maritalStrings[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: maritalStrings,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),
                    Text("Types of Relationship looking for"),
                    Wrap(
                      children: [
                        for (var i in relationStrings)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: GestureDetector(
                              onTap: () {
                                print("Tapped");
                                if (user.relTypes!.contains(i)) {
                                  DatabaseService.updateUserField(
                                    widget.botId,
                                    {
                                      "relTypes": FieldValue.arrayRemove([i]),
                                    },
                                  );
                                  load();
                                  setState(() {});
                                } else {
                                  DatabaseService.updateUserField(
                                    widget.botId,
                                    {
                                      "relTypes": FieldValue.arrayUnion([i]),
                                    },
                                  );
                                  load();
                                  setState(() {});
                                }
                              },
                              child: Chip(
                                backgroundColor: user.relTypes!.contains(i)
                                    ? kPrimaryColor
                                    : kSecondaryColor,
                                label: Text(
                                  i,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // ============ TOP PICKS FIELDS ============
                    SizedBox(height: getProportionateScreenHeight(20)),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.star, color: kPrimaryColor),
                          SizedBox(width: 8),
                          Text(
                            "Top Picks Profile Fields",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: getProportionateScreenHeight(10)),

                    // About Me
                    Text("About Me"),
                    SizedBox(height: 5),
                    TextFormField(
                      controller: aboutCtr,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Write something about this bot...",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        DatabaseService.updateUserField(widget.botId, {
                          "about": value,
                        });
                      },
                    ),
                    SizedBox(height: getProportionateScreenHeight(15)),

                    // Diet
                    Text("Diet"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: dietStrings.indexOf(user.diet ?? ''),
                          onChanged: (val) {
                            DatabaseService.updateUserField(widget.botId, {
                              "diet": dietStrings[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: dietStrings,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),

                    // Zodiac
                    Text("Zodiac Sign"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: zodiacStrings.indexOf(user.zodiac ?? ''),
                          onChanged: (val) {
                            DatabaseService.updateUserField(widget.botId, {
                              "zodiac": zodiacStrings[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: zodiacStrings,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),

                    // Religion
                    Text("Religion"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: religionStrings.indexOf(user.religion ?? ''),
                          onChanged: (val) {
                            DatabaseService.updateUserField(widget.botId, {
                              "religion": religionStrings[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: religionStrings,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),

                    // Smoker
                    Text("Smoking Habit"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: smokerStrings.indexOf(user.smoker ?? ''),
                          onChanged: (val) {
                            DatabaseService.updateUserField(widget.botId, {
                              "smoker": smokerStrings[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: smokerStrings,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),

                    // Drinking
                    Text("Drinking Habit"),
                    Wrap(
                      children: [
                        ChipsChoice<int>.single(
                          choiceStyle: choiceActiveStyle,
                          value: drinkingStrings.indexOf(user.drinking ?? ''),
                          onChanged: (val) {
                            DatabaseService.updateUserField(widget.botId, {
                              "drinking": drinkingStrings[val],
                            });
                            load();
                          },
                          choiceItems: C2Choice.listFrom<int, String>(
                            source: drinkingStrings,
                            value: (i, v) => i,
                            label: (i, v) => v,
                          ),
                        ),
                      ],
                    ),

                    // Interests (Multi-select)
                    Text("Interests"),
                    Wrap(
                      children: [
                        for (var i in interestStrings)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: GestureDetector(
                              onTap: () {
                                List<String> currentInterests =
                                    user.interests ?? [];
                                if (currentInterests.contains(i)) {
                                  DatabaseService.updateUserField(
                                    widget.botId,
                                    {
                                      "interests": FieldValue.arrayRemove([i]),
                                    },
                                  );
                                } else {
                                  DatabaseService.updateUserField(
                                    widget.botId,
                                    {
                                      "interests": FieldValue.arrayUnion([i]),
                                    },
                                  );
                                }
                                load();
                                setState(() {});
                              },
                              child: Chip(
                                backgroundColor:
                                    (user.interests ?? []).contains(i)
                                    ? kPrimaryColor
                                    : kSecondaryColor,
                                label: Text(
                                  i,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: getProportionateScreenHeight(20)),
                  ],
                ),
              ),
            ),
    );
  }

  TextEditingController uNameCtr = new TextEditingController();

  TextFormField buildUserNameFormField() {
    return TextFormField(
      controller: uNameCtr,
      keyboardType: TextInputType.name,
      // onChanged: (value) {
      //   if (value.isNotEmpty) {
      //     removeError(error: kEmailNullError);
      //   }
      //   return null;
      // },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kEmailNullError);
          return "";
        }
        return null;
      },
      decoration: InputDecoration(
        helperText: ' ',

        labelText: "Username",
        hintText: "Enter Username",
        // If  you are using latest version of flutter then lable text and hint text shown like this
        // if you r using flutter less then 1.20.* then maybe this is not working properly
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: CustomSurffixIcon(iconData: Icons.person),
      ),
    );
  }

  TextEditingController stateCtr = new TextEditingController();

  TextFormField buildStateFormField() {
    return TextFormField(
      controller: stateCtr,
      keyboardType: TextInputType.name,
      // onChanged: (value) {
      //   if (value.isNotEmpty) {
      //     removeError(error: kEmailNullError);
      //   }
      //   return null;
      // },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kEmailNullError);
          return "";
        }
        return null;
      },
      decoration: InputDecoration(
        helperText: ' ',
        labelText: "State",
        hintText: "Enter State",
        // If  you are using latest version of flutter then lable text and hint text shown like this
        // if you r using flutter less then 1.20.* then maybe this is not working properly
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: CustomSurffixIcon(iconData: Icons.pin_drop),
      ),
    );
  }

  TextEditingController cityCtr = new TextEditingController();

  TextFormField buildCityFormField() {
    return TextFormField(
      controller: cityCtr,
      keyboardType: TextInputType.name,
      // onChanged: (value) {
      //   if (value.isNotEmpty) {
      //     removeError(error: kEmailNullError);
      //   }
      //   return null;
      // },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kEmailNullError);
          return "";
        }
        return null;
      },
      decoration: InputDecoration(
        helperText: ' ',
        labelText: "City",
        hintText: "Enter City",
        // If  you are using latest version of flutter then lable text and hint text shown like this
        // if you r using flutter less then 1.20.* then maybe this is not working properly
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: CustomSurffixIcon(iconData: Icons.pin_drop),
      ),
    );
  }

  TextEditingController ageCtr = new TextEditingController();

  TextFormField buildAgeFormField() {
    return TextFormField(
      controller: ageCtr,
      keyboardType: TextInputType.number,
      // onChanged: (value) {
      //   if (value.isNotEmpty) {
      //     removeError(error: kEmailNullError);
      //   }
      //   return null;
      // },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kEmailNullError);
          return "";
        }
        return null;
      },
      decoration: InputDecoration(
        helperText: ' ',
        labelText: "Age",
        hintText: "Enter Age",
        // If  you are using latest version of flutter then lable text and hint text shown like this
        // if you r using flutter less then 1.20.* then maybe this is not working properly
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: CustomSurffixIcon(iconData: Icons.date_range),
      ),
    );
  }

  final List<String> errors = [];

  void addError(String error) {
    if (!errors.contains(error))
      setState(() {
        errors.add(error);
      });
  }

  void removeError(String error) {
    if (errors.contains(error))
      setState(() {
        errors.remove(error);
      });
  }
}
