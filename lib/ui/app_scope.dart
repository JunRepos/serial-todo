import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';

/// Repository와 UI 설정을 위젯 트리에 전달. Repository 변경 시 의존 위젯이 다시 그려진다.
class AppScope extends InheritedNotifier<Repository> {
  const AppScope({super.key, required Repository repo, required this.prefs, required super.child})
    : super(notifier: repo);

  final SharedPreferences prefs;

  static AppScope _of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!;

  /// 데이터가 바뀌면 다시 그려진다
  static Repository watch(BuildContext c) => _of(c).notifier!;

  /// 구독 없이 접근
  static Repository repo(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static SharedPreferences prefsOf(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.prefs;
}
