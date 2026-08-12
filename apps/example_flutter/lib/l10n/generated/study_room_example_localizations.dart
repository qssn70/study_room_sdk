import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'study_room_example_localizations_en.dart';
import 'study_room_example_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of StudyRoomExampleLocalizations
/// returned by `StudyRoomExampleLocalizations.of(context)`.
///
/// Applications need to include `StudyRoomExampleLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/study_room_example_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: StudyRoomExampleLocalizations.localizationsDelegates,
///   supportedLocales: StudyRoomExampleLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the StudyRoomExampleLocalizations.supportedLocales
/// property.
abstract class StudyRoomExampleLocalizations {
  StudyRoomExampleLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static StudyRoomExampleLocalizations of(BuildContext context) {
    return Localizations.of<StudyRoomExampleLocalizations>(
      context,
      StudyRoomExampleLocalizations,
    )!;
  }

  static const LocalizationsDelegate<StudyRoomExampleLocalizations> delegate =
      _StudyRoomExampleLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @styleSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get styleSplit;

  /// No description provided for @styleCentered.
  ///
  /// In en, this message translates to:
  /// **'Centered'**
  String get styleCentered;

  /// No description provided for @styleImmersive.
  ///
  /// In en, this message translates to:
  /// **'Immersive'**
  String get styleImmersive;

  /// No description provided for @openRoomWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Open live room workflow'**
  String get openRoomWorkflow;

  /// No description provided for @rooms.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get rooms;

  /// No description provided for @workflowTitle.
  ///
  /// In en, this message translates to:
  /// **'Study Room 0.4 workflow'**
  String get workflowTitle;

  /// No description provided for @membersTab.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersTab;

  /// No description provided for @requestsTab.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requestsTab;

  /// No description provided for @configurationInstructions.
  ///
  /// In en, this message translates to:
  /// **'Run with --dart-define=STUDY_ROOM_API_URL=http://localhost:3000 --dart-define=STUDY_ROOM_REALTIME_URL=ws://localhost:3000/v1/realtime --dart-define=STUDY_ROOM_DEV_TOKEN_URL=http://localhost:4000/token.'**
  String get configurationInstructions;

  /// No description provided for @demoRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Demo Focus Room'**
  String get demoRoomTitle;

  /// No description provided for @currentUserName.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get currentUserName;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to start the live room workflow. Check the configuration and try again.'**
  String get startupFailed;
}

class _StudyRoomExampleLocalizationsDelegate
    extends LocalizationsDelegate<StudyRoomExampleLocalizations> {
  const _StudyRoomExampleLocalizationsDelegate();

  @override
  Future<StudyRoomExampleLocalizations> load(Locale locale) {
    return SynchronousFuture<StudyRoomExampleLocalizations>(
      lookupStudyRoomExampleLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_StudyRoomExampleLocalizationsDelegate old) => false;
}

StudyRoomExampleLocalizations lookupStudyRoomExampleLocalizations(
  Locale locale,
) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return StudyRoomExampleLocalizationsEn();
    case 'zh':
      return StudyRoomExampleLocalizationsZh();
  }

  throw FlutterError(
    'StudyRoomExampleLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
