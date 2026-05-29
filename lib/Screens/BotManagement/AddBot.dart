import 'package:viora/Services/DatabaseService.dart';
import 'package:viora/Services/ProgressBarHelper.dart';
import 'package:viora/components/custom_surfix_icon.dart';
import 'package:viora/components/default_button.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:viora/components/customAppBar.dart';
import 'package:viora/components/form_error.dart';
import '../../constants.dart';
import '../../size_config.dart';

class AddBot extends StatefulWidget {
  @override
  _AddBotState createState() => _AddBotState();
}

class _AddBotState extends State<AddBot> {
  int currentPage = 0;
  int _value = 0;
  String gender = 'Male';
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: getProportionateScreenWidth(20),
          vertical: getProportionateScreenWidth(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (index) => buildDot(index)),
        ),
      ),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),

        child: CustomAppBar(title: "Add new Bot"),
      ),

      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: <Widget>[
              Expanded(
                child: PageView(
                  onPageChanged: (index) {
                    setState(() {
                      currentPage = index;
                    });
                  },
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Gender",
                            style: TextStyle(
                              fontSize: getProportionateScreenWidth(36),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "(Can't be changed later)",
                            style: TextStyle(
                              fontSize: getProportionateScreenWidth(12),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: getProportionateScreenHeight(50)),
                          GridView.count(
                            crossAxisCount: 2,
                            padding: EdgeInsets.all(
                              getProportionateScreenWidth(20),
                            ),
                            crossAxisSpacing: 20,
                            physics: NeverScrollableScrollPhysics(),
                            scrollDirection: Axis.vertical,
                            shrinkWrap: true,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() {
                                  _value = 0;
                                  gender = 'Male';
                                }),
                                child: Container(
                                  width: getProportionateScreenWidth(150),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(20),
                                    ),
                                    border: Border.all(
                                      width: _value == 0 ? 2 : 1,
                                      color: _value == 0
                                          ? kPrimaryColor
                                          : kSecondaryColor,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      getProportionateScreenWidth(30),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.asset("assets/svg/male.svg"),
                                        Text(
                                          "Male",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize:
                                                getProportionateScreenWidth(24),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _value = 1;
                                  gender = 'Female';
                                }),
                                child: Container(
                                  width: getProportionateScreenWidth(150),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(20),
                                    ),
                                    border: Border.all(
                                      width: _value == 1 ? 2 : 1,
                                      color: _value == 1
                                          ? kPrimaryColor
                                          : kSecondaryColor,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      getProportionateScreenWidth(30),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          "assets/svg/female.svg",
                                        ),
                                        Text(
                                          "Female",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize:
                                                getProportionateScreenWidth(24),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 80.0),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Complete Profile",
                                style: TextStyle(
                                  fontSize: getProportionateScreenWidth(36),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(
                                height: getProportionateScreenHeight(50),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    children: [
                                      buildUserNameFormField(),
                                      SizedBox(
                                        height: getProportionateScreenHeight(
                                          10,
                                        ),
                                      ),
                                      buildStateFormField(),
                                      SizedBox(
                                        height: getProportionateScreenHeight(
                                          10,
                                        ),
                                      ),
                                      buildCityFormField(),
                                      SizedBox(
                                        height: getProportionateScreenHeight(
                                          10,
                                        ),
                                      ),
                                      buildAgeFormField(),
                                      FormError(errors: errors),
                                      SizedBox(
                                        height: getProportionateScreenHeight(
                                          20,
                                        ),
                                      ),
                                      DefaultButton(
                                        text: "Continue",
                                        press: () async {
                                          FocusScope.of(
                                            context,
                                          ).requestFocus(FocusNode());
                                          if (_formKey.currentState!
                                              .validate()) {
                                            ProgressBarHelper.load(context);
                                            ProgressBarHelper.pr.show();

                                            UserDetails user = UserDetails(
                                              isDisabled: false,
                                              unseenCount: 0,
                                              notiCount: 0,
                                              isTyping: '',
                                              gender: gender,
                                              name: uNameCtr.text,
                                              images: [],
                                              joiningDate: DateTime.now(),
                                              age: int.parse(ageCtr.text),
                                              city: cityCtr.text,
                                              coins: 10,
                                              fcmToken: "Admin",
                                              isOnline: true,
                                              lastOnline: DateTime.now(),
                                              maritalStatus: "Single",
                                              sexualOrientation: ["Straight"],
                                              relTypes: ["Open to anything"],
                                              state: stateCtr.text,
                                            );
                                            await DatabaseService.addBot(
                                              context,
                                              user,
                                            );
                                            ProgressBarHelper.pr.hide();
                                            Navigator.pop(context);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AnimatedContainer buildDot(int index) {
    return AnimatedContainer(
      duration: kAnimationDuration,
      margin: EdgeInsets.only(right: 5),
      height: 12,
      width: currentPage == index ? 40 : 18,
      decoration: BoxDecoration(
        color: currentPage == index ? kPrimaryColor : Color(0xFFD8D8D8),
        borderRadius: BorderRadius.circular(9),
      ),
    );
  }

  TextEditingController uNameCtr = new TextEditingController();

  TextFormField buildUserNameFormField() {
    return TextFormField(
      maxLength: 15,

      controller: uNameCtr,
      keyboardType: TextInputType.name,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return null;
      },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kReqError);
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
      maxLength: 15,

      controller: stateCtr,
      keyboardType: TextInputType.name,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return null;
      },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kReqError);
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
      maxLength: 15,

      controller: cityCtr,
      keyboardType: TextInputType.name,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        return null;
      },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kReqError);
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
      maxLength: 2,

      controller: ageCtr,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        if (value.isNotEmpty) {
          removeError(kReqError);
        }
        if (double.parse(value) >= 18) {
          removeError(kAgeError);
        }
        return null;
      },
      validator: (value) {
        if (value!.isEmpty) {
          addError(kReqError);
          return "";
        } else if (double.parse(value) < 18) {
          addError(kAgeError);

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
