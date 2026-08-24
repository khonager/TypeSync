import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/app_router.dart';

/// The small, durable part of the UI state that is needed to recover after a
/// browser refresh. Note contents remain owned by the normal data providers.
class NavigationSnapshot {
  const NavigationSnapshot({
    this.routeName = AppRouter.home,
    this.noteId,
    this.folderId,
    this.primaryNoteId,
    this.secondaryNoteId,
    this.secondaryFolderId,
    this.homeFolderId,
    this.homeTab = 'files',
  });

  final String routeName;
  final String? noteId;
  final String? folderId;
  final String? primaryNoteId;
  final String? secondaryNoteId;
  final String? secondaryFolderId;
  final String? homeFolderId;
  final String homeTab;

  NavigationSnapshot copyWith({
    String? routeName,
    String? noteId,
    String? folderId,
    String? primaryNoteId,
    String? secondaryNoteId,
    String? secondaryFolderId,
    String? homeFolderId,
    String? homeTab,
    bool clearRouteArguments = false,
  }) {
    return NavigationSnapshot(
      routeName: routeName ?? this.routeName,
      noteId: clearRouteArguments ? null : (noteId ?? this.noteId),
      folderId: clearRouteArguments ? null : (folderId ?? this.folderId),
      primaryNoteId:
          clearRouteArguments ? null : (primaryNoteId ?? this.primaryNoteId),
      secondaryNoteId: clearRouteArguments
          ? null
          : (secondaryNoteId ?? this.secondaryNoteId),
      secondaryFolderId: clearRouteArguments
          ? null
          : (secondaryFolderId ?? this.secondaryFolderId),
      homeFolderId: homeFolderId ?? this.homeFolderId,
      homeTab: homeTab ?? this.homeTab,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'routeName': routeName,
        'noteId': noteId,
        'folderId': folderId,
        'primaryNoteId': primaryNoteId,
        'secondaryNoteId': secondaryNoteId,
        'secondaryFolderId': secondaryFolderId,
        'homeFolderId': homeFolderId,
        'homeTab': homeTab,
      };

  factory NavigationSnapshot.fromJson(Map<String, dynamic> json) {
    return NavigationSnapshot(
      routeName: json['routeName'] as String? ?? AppRouter.home,
      noteId: json['noteId'] as String?,
      folderId: json['folderId'] as String?,
      primaryNoteId: json['primaryNoteId'] as String?,
      secondaryNoteId: json['secondaryNoteId'] as String?,
      secondaryFolderId: json['secondaryFolderId'] as String?,
      homeFolderId: json['homeFolderId'] as String?,
      homeTab: json['homeTab'] as String? ?? 'files',
    );
  }
}

class NavigationStateService {
  NavigationStateService._();

  static final NavigationStateService instance = NavigationStateService._();
  static const _preferencePrefix = 'typesync_navigation_v1_';

  String? _workspaceId;
  NavigationSnapshot _snapshot = const NavigationSnapshot();
  Future<void> _writeQueue = Future<void>.value();

  Future<NavigationSnapshot> activate(String workspaceId) async {
    await _writeQueue;
    final prefs = await SharedPreferences.getInstance();
    NavigationSnapshot snapshot = const NavigationSnapshot();
    final stored = prefs.getString('$_preferencePrefix$workspaceId');
    if (stored != null) {
      try {
        snapshot = NavigationSnapshot.fromJson(
          jsonDecode(stored) as Map<String, dynamic>,
        );
      } catch (_) {
        await prefs.remove('$_preferencePrefix$workspaceId');
      }
    }
    _workspaceId = workspaceId;
    _snapshot = snapshot;
    return snapshot;
  }

  void recordHomeState({required String tab, String? folderId}) {
    if (_workspaceId == null) return;
    _snapshot = NavigationSnapshot(
      routeName: AppRouter.home,
      homeFolderId: folderId,
      homeTab: tab,
    );
    _persist();
  }

  void recordRoute(RouteSettings settings) {
    if (_workspaceId == null) return;
    final name = settings.name;
    if (name == null) return;

    if (name == AppRouter.home) {
      _snapshot = _snapshot.copyWith(
        routeName: AppRouter.home,
        clearRouteArguments: true,
      );
      _persist();
      return;
    }

    final arguments = settings.arguments;
    final values = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    _snapshot = NavigationSnapshot(
      routeName: name,
      noteId: values['noteId'] as String?,
      folderId: values['folderId'] as String?,
      primaryNoteId: values['primaryNoteId'] as String?,
      secondaryNoteId: values['secondaryNoteId'] as String?,
      secondaryFolderId: values['secondaryFolderId'] as String?,
      homeFolderId: _snapshot.homeFolderId,
      homeTab: _snapshot.homeTab,
    );
    _persist();
  }

  void _persist() {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;
    final encodedSnapshot = jsonEncode(_snapshot.toJson());
    _writeQueue = _writeQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_preferencePrefix$workspaceId',
        encodedSnapshot,
      );
    });
  }
}

/// Keeps ordinary named-route navigation in the same refresh snapshot as note
/// routes. The initial home route is deliberately ignored until a workspace
/// has been activated by the authenticated shell.
class NavigationStateObserver extends NavigatorObserver {
  void _record(Route<dynamic>? route) {
    if (route == null) return;
    NavigationStateService.instance.recordRoute(route.settings);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _record(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record(newRoute);
  }
}
