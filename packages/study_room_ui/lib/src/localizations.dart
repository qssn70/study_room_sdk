import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class StudyRoomLocalizations {
  const StudyRoomLocalizations(this.locale);
  final Locale locale;

  static const delegate = _StudyRoomLocalizationsDelegate();
  static const supportedLocales = [Locale('en'), Locale('zh')];
  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static StudyRoomLocalizations of(BuildContext context) {
    final value = maybeOf(context);
    assert(
      value != null,
      'StudyRoomLocalizations is not available in this context',
    );
    return value ?? forLocale(Localizations.localeOf(context));
  }

  static StudyRoomLocalizations? maybeOf(BuildContext context) =>
      Localizations.of<StudyRoomLocalizations>(context, StudyRoomLocalizations);

  static StudyRoomLocalizations forLocale(Locale locale) =>
      StudyRoomLocalizations(
        locale.languageCode == 'zh' ? const Locale('zh') : const Locale('en'),
      );

  bool get _zh => locale.languageCode == 'zh';
  String get rooms => _zh ? '自习房间' : 'Study rooms';
  String get createRoom => _zh ? '创建房间' : 'Create room';
  String get roomTitle => _zh ? '房间名称' : 'Room title';
  String get joinRoom => _zh ? '申请加入' : 'Request access';
  String get roomId => _zh ? '房间 ID' : 'Room ID';
  String get pendingRequests => _zh ? '待审批申请' : 'Pending requests';
  String get myRequests => _zh ? '我的申请' : 'My requests';
  String get approve => _zh ? '批准' : 'Approve';
  String get reject => _zh ? '拒绝' : 'Reject';
  String get cancel => _zh ? '取消' : 'Cancel';
  String get members => _zh ? '成员管理' : 'Members';
  String get transferOwnership => _zh ? '转让房主' : 'Transfer ownership';
  String get remove => _zh ? '移除' : 'Remove';
  String get retry => _zh ? '重试' : 'Retry';
  String get refresh => _zh ? '刷新' : 'Refresh';
  String get noRooms => _zh ? '还没有加入任何房间' : 'You have not joined a room yet';
  String get noRequests => _zh ? '暂无申请' : 'No requests';
  String get open => _zh ? '打开' : 'Open';
  String get owner => _zh ? '房主' : 'Owner';
  String get member => _zh ? '成员' : 'Member';
  String get pending => _zh ? '待审批' : 'Pending';
  String get approved => _zh ? '已批准' : 'Approved';
  String get rejected => _zh ? '已拒绝' : 'Rejected';
  String get cancelled => _zh ? '已取消' : 'Cancelled';
  String get requestSubmitted => _zh ? '加入申请已提交' : 'Join request submitted';
  String get operationFailed =>
      _zh ? '操作失败，请重试' : 'Operation failed. Please retry.';
  String memberCount(int count) => _zh ? '$count 位成员' : '$count members';
}

class _StudyRoomLocalizationsDelegate
    extends LocalizationsDelegate<StudyRoomLocalizations> {
  const _StudyRoomLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['en', 'zh'].contains(locale.languageCode);
  @override
  Future<StudyRoomLocalizations> load(Locale locale) =>
      SynchronousFuture(StudyRoomLocalizations.forLocale(locale));
  @override
  bool shouldReload(_StudyRoomLocalizationsDelegate old) => false;
}
