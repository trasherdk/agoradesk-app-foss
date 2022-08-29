import 'dart:async';

import 'package:agoradesk/core/api/api_client.dart';
import 'package:agoradesk/core/app_parameters.dart';
import 'package:agoradesk/core/app_state.dart';
import 'package:agoradesk/core/utils/error_parse_mixin.dart';
import 'package:agoradesk/features/ads/data/models/asset.dart';
import 'package:agoradesk/features/auth/data/services/auth_service.dart';
import 'package:agoradesk/features/wallet/data/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

/// Wallet data polling
const _kWalletPollingSeconds = 10;

class PollingService with ErrorParseMixin {
  PollingService({
    required this.api,
    required this.walletService,
    required this.appState,
    required this.authService,
  });

  final ApiClient api;
  final WalletService walletService;
  final AuthService authService;
  final AppState appState;
  bool _loadingBalance = false;
  Timer? _timer;

  Future init() async {
    ///
    /// Polling balance from the server
    ///
    ///
    Future.delayed(const Duration(seconds: 6)).then((value) => getBalances());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: _kWalletPollingSeconds), (_) => getBalances());
  }

  ///
  /// Get balances
  ///
  Future getBalances() async {
    if (authService.isAuthenticated) {
      if (!_loadingBalance) {
        _loadingBalance = true;
        appState.notificationsLoading = true;
        if (GetIt.I<AppParameters>().isAgora) {
          final resBtc = await walletService.getBalance(Asset.BTC);
          final resXmr = await walletService.getBalance(Asset.XMR);
          if (resBtc.isRight && resXmr.isRight) {
            appState.balanceController.add([
              resXmr.right,
              resBtc.right,
            ]);
          } else {
            debugPrint(
                '++++[Polling service - getBalances error] - BTC ${resBtc.left.statusCode} - XMR ${resXmr.left.statusCode}');
          }
        } else {
          final resXmr = await walletService.getBalance(Asset.XMR);
          if (resXmr.isRight) {
            appState.balanceController.add([
              resXmr.right,
            ]);
          } else {
            debugPrint('++++[Polling service - getBalances error] - XMR ${resXmr.left.statusCode}');
          }
        }
        _loadingBalance = false;
      }
    }
  }
}
