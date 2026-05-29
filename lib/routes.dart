import 'package:viora/Screens/AdminScreens/Spamers.dart';
import 'package:viora/Screens/AdminScreens/TransactionsScreen.dart';
import 'package:viora/Screens/AdminScreens/adminChatRooms.dart';
import 'package:viora/Screens/BotManagement/DiabledBots.dart';
import 'package:viora/Screens/CompleteProfile/completeProfile.dart';
import 'package:viora/Screens/EditProfile/editProfile.dart';
import 'package:viora/Screens/Home/home.dart';
import 'package:viora/Screens/Login_Signup/loginScreen.dart';
import 'package:viora/Screens/MyPhotos/myPhotos.dart';
import 'package:viora/Screens/ProfileScreen/profileScreen.dart';
import 'package:viora/Screens/Verification/LivenessVerificationScreen.dart';
import 'package:viora/Screens/Verification/ProfileCorrectionScreen.dart';
import 'package:flutter/widgets.dart';
import 'Screens/BotManagement/botChatScreen.dart';
import 'Screens/BotManagement/botHome.dart';
import 'Screens/BotManagement/botNotifications.dart';
import 'Screens/Home/homeScreen.dart';
import 'Screens/MessagesScreen/message_screen.dart';
import 'Screens/Splash/splashScreen.dart';
import 'package:viora/Screens/AdminScreens/reportScreen.dart';
import 'package:viora/Screens/AdminScreens/AdminPlans.dart';
import 'package:viora/Screens/AdminScreens/MaleUsers.dart';
import 'package:viora/Screens/AdminScreens/FemaleUsers.dart';
import 'package:viora/Screens/AdminScreens/SearchUsers.dart';

import 'Screens/SupportScreen/supportScreen.dart';
import 'Screens/SettingsScreen/settingsScreen.dart';

// We use name route
// All our routes will be available here
final Map<String, WidgetBuilder> routes = {
  SplashScreen.routeName: (context) => SplashScreen(),
  HomeScreen.routeName: (context) => HomeScreen(),
  LoginScreen.routeName: (context) => LoginScreen(),
  CompleteProfile.routeName: (_) => CompleteProfile(),
  Home.routeName: (_) => Home(),
  EditProfile.routeName: (_) => EditProfile(),
  // ProfileScreen.routeName: (_) => ProfileScreen(uid: ''),
  MyPhotos.routeName: (_) => MyPhotos(),
  AdminChatRooms.routeName: (_) => AdminChatRooms(),
  BotHome.routeName: (_) => BotHome(),
  TransactionsScreen.routeName: (_) => TransactionsScreen(),
  ReportScreen.routeName: (_) => ReportScreen(),
  AdminPlans.routeName: (_) => AdminPlans(),
  Spamers.routeName: (_) => Spamers(),
  MaleUsers.routeName: (_) => MaleUsers(),
  FemaleUsers.routeName: (_) => FemaleUsers(),
  SearchUser.routeName: (_) => SearchUser(),
  DisabledBots.routeName: (_) => DisabledBots(),
  SupportScreen.routeName: (_) => SupportScreen(canPop: true),
  MessagesScreen.routeName: (_) => MessagesScreen(uId: ''),
  BotChatsScreen.routeName: (_) => BotChatsScreen(botId: ''),
  BotNotificationScreen.routeName: (_) => BotNotificationScreen(botId: ''),
  LivenessVerificationScreen.routeName: (_) => LivenessVerificationScreen(),
  ProfileCorrectionScreen.routeName: (_) => ProfileCorrectionScreen(),
  SettingsScreen.routeName: (_) => SettingsScreen(),
};
