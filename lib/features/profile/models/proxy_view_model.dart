import 'dart:async';

import 'package:agoradesk/core/app_parameters.dart';
import 'package:agoradesk/core/app_shared_prefs.dart';
import 'package:agoradesk/core/packages/socks_proxy/socks_proxy.dart';
import 'package:agoradesk/core/utils/error_parse_mixin.dart';
import 'package:agoradesk/core/utils/proxy_helper_dart.dart';
import 'package:agoradesk/core/utils/validator_mixin.dart';
import 'package:agoradesk/core/widgets/branded/agora_dialog_close.dart';
import 'package:agoradesk/features/account/data/services/account_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:vm/vm.dart';

///
/// Proxy example 69.194.181.6:7497
///
/// const url = 'https://api.ipify.org';
/// final aa = await _dio.get(url);
///

class ProxyViewModel extends ViewModel with ValidatorMixin, ErrorParseMixin {
  ProxyViewModel({
    required AccountService accountService,
  }) : _accountService = accountService;

  final AccountService _accountService;

  final ctrlServer = TextEditingController();
  final ctrlPort = TextEditingController();
  final ctrlUsername = TextEditingController();
  final ctrlPassword = TextEditingController();

  late bool _isProxyOn;
  bool _loading = false;
  bool _readyToSwitchOnProxy = false;
  bool _proxyAvailable = false;

  bool get proxyAvailable => _proxyAvailable;

  set proxyAvailable(bool val) => updateWith(proxyAvailable: val);

  bool get isProxyOn => _isProxyOn;

  set isProxyOn(bool val) => updateWith(isProxyOn: val);

  bool get loading => _loading;

  set loading(bool val) => updateWith(loading: val);

  bool get readyToSwitchOnProxy => _readyToSwitchOnProxy;

  set readyToSwitchOnProxy(bool val) => updateWith(readyToSwitchOnProxy: val);

  @override
  Future<void> init() async {
    isProxyOn = GetIt.I<AppParameters>().proxy ?? false;

    ctrlServer.text = AppSharedPrefs().proxyServer;
    ctrlPort.text = AppSharedPrefs().proxyPort;
    ctrlUsername.text = AppSharedPrefs().proxyUsername;
    ctrlPassword.text = AppSharedPrefs().proxyPassword;

    ctrlServer.addListener(_checkIsReadyToSetProxy);
    ctrlPort.addListener(_checkIsReadyToSetProxy);
    ctrlUsername.addListener(_checkIsReadyToSetProxy);
    ctrlPassword.addListener(_checkIsReadyToSetProxy);
    super.init();
  }

  void _checkIsReadyToSetProxy() {
    if (ctrlServer.text.isNotEmpty && ctrlPort.text.isNotEmpty) {
      if ((ctrlUsername.text.isNotEmpty && ctrlPassword.text.isNotEmpty) || ctrlUsername.text.isEmpty) {
        readyToSwitchOnProxy = true;
      } else {
        readyToSwitchOnProxy = false;
      }
    } else {
      readyToSwitchOnProxy = false;
    }
  }

  Future switchProxy(BuildContext context, bool val) async {
    loading = true;
    isProxyOn = !isProxyOn;
    await AppSharedPrefs().setBool(AppSharedPrefsKey.proxyEnabled, val: isProxyOn);
    GetIt.I<AppParameters>().proxy = isProxyOn;
    await _setProxyData();
    loading = false;
    if (val) {
      _displayMessage(context);
    }
  }

  Future saveProxy(BuildContext context) async {
    loading = true;
    await AppSharedPrefs().setString(AppSharedPrefsKey.proxyServer, ctrlServer.text);
    await AppSharedPrefs().setString(AppSharedPrefsKey.proxyPort, ctrlPort.text);
    await AppSharedPrefs().setString(AppSharedPrefsKey.proxyUsername, ctrlUsername.text);
    await AppSharedPrefs().setString(AppSharedPrefsKey.proxyPassword, ctrlPassword.text);
    // await AppSharedPrefs().setBool(AppSharedPrefsKey.proxyEnabled, val: true);
    // GetIt.I<AppParameters>().proxy = true;
    // isProxyOn = true;
    await _setProxyData(fromSave: true);
    loading = false;
    _displayMessage(context);
  }

  Future _setProxyData({bool? fromSave}) async {
    final proxyAddress = getProxyAddress();
    if (isProxyOn || fromSave == true) {
      SocksProxy.setProxy('SOCKS5 $proxyAddress');
      await Future.delayed(const Duration(seconds: 1));
      final res = await _accountService.checkProxyAvailable();
      if (res.isRight) {
        proxyAvailable = true;
        await AppSharedPrefs().setBool(AppSharedPrefsKey.proxyEnabled, val: true);
        GetIt.I<AppParameters>().proxy = true;
      } else {
        proxyAvailable = false;
        await AppSharedPrefs().setBool(AppSharedPrefsKey.proxyEnabled, val: false);
        GetIt.I<AppParameters>().proxy = false;
        SocksProxy.setProxy('DIRECT');
      }
    } else {
      await AppSharedPrefs().setBool(AppSharedPrefsKey.proxyEnabled, val: false);
      GetIt.I<AppParameters>().proxy = false;
      SocksProxy.setProxy('DIRECT');
    }
  }

  void _displayMessage(BuildContext context) {
    if (proxyAvailable) {
      isProxyOn = true;
      showDialog(
        barrierDismissible: true,
        context: context,
        builder: (_) => const AgoraDialogClose(
          title: 'Proxy is on',
          text: 'Now app make requests with the proxy',
        ),
      );
    } else {
      isProxyOn = false;
      showDialog(
        barrierDismissible: true,
        context: context,
        builder: (_) => const AgoraDialogClose(
          title: 'Proxy unavailable',
          text: 'Please check the proxy data or use another proxy.',
        ),
      );
    }
  }

  void updateWith({
    bool? loading,
    bool? isProxyOn,
    bool? proxyAvailable,
    bool? readyToSwitchOnProxy,
  }) {
    _loading = loading ?? _loading;
    _isProxyOn = isProxyOn ?? _isProxyOn;
    _proxyAvailable = proxyAvailable ?? _proxyAvailable;
    _readyToSwitchOnProxy = readyToSwitchOnProxy ?? _readyToSwitchOnProxy;
    notifyListeners();
  }

  @override
  void dispose() {
    ctrlServer.dispose();
    ctrlPort.dispose();
    ctrlPassword.dispose();
    ctrlPort.dispose();
    super.dispose();
  }
}
