import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';
import 'weight_screen.dart';

/// ホーム（下部のタブ）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // 履歴から日付をタップされたときに「きょう」タブでその日を開くための依頼。
  // 同じ日付を2回続けてタップしても開き直せるよう、回数も一緒に渡す。
  DateTime? _openDate;
  int _openRequest = 0;

  void _openDay(DateTime date) => setState(() {
    _index = 0;
    _openDate = date;
    _openRequest++;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStackで4画面とも保持する（タブを切り替えても入力途中の文章や
      // スクロール位置が消えないように）。
      body: IndexedStack(
        index: _index,
        children: [
          TodayScreen(
            profile: widget.profile,
            openDate: _openDate,
            openRequest: _openRequest,
          ),
          HistoryScreen(profile: widget.profile, onOpenDay: _openDay),
          WeightScreen(profile: widget.profile),
          SettingsScreen(profile: widget.profile),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'きょう',
          ),
          NavigationDestination(
            icon: Icon(Icons.insert_chart_outlined),
            selectedIcon: Icon(Icons.insert_chart),
            label: '履歴',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight_outlined),
            selectedIcon: Icon(Icons.monitor_weight),
            label: '体重',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
