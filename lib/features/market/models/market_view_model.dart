//ignore: use_build_context_synchronously

import 'dart:async';
import 'dart:ui';

import 'package:agoradesk/core/app_parameters.dart';
import 'package:agoradesk/core/app_shared_prefs.dart';
import 'package:agoradesk/core/app_state_v1.dart';
import 'package:agoradesk/core/extensions/capitalized_first_letter.dart';
import 'package:agoradesk/core/models/pagination.dart';
import 'package:agoradesk/core/packages/mapbox/places_search.dart';
import 'package:agoradesk/core/packages/mapbox/predictions.dart';
import 'package:agoradesk/core/packages/text_field_search/textfield_search.dart';
import 'package:agoradesk/core/theme/theme.dart';
import 'package:agoradesk/core/translations/countries_coordinates_consts.dart';
import 'package:agoradesk/core/translations/country_info_mixin.dart';
import 'package:agoradesk/core/translations/payment_method_mixin.dart';
import 'package:agoradesk/core/utils/error_parse_mixin.dart';
import 'package:agoradesk/features/ads/data/models/ad_model.dart';
import 'package:agoradesk/features/ads/data/models/asset.dart';
import 'package:agoradesk/features/ads/data/models/country_code_model.dart';
import 'package:agoradesk/features/ads/data/models/country_model.dart';
import 'package:agoradesk/features/ads/data/models/currency_model.dart';
import 'package:agoradesk/features/ads/data/models/payment_method_model.dart';
import 'package:agoradesk/features/ads/data/models/trade_type.dart';
import 'package:agoradesk/features/ads/data/repositories/ads_repository.dart';
import 'package:agoradesk/features/app_update/data/services/app_update_service.dart';
import 'package:agoradesk/features/app_update/screens/app_update_widget.dart';
import 'package:agoradesk/features/auth/data/services/auth_service.dart';
import 'package:collection/collection.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:vm/vm.dart';

const kDefaultCountry = CountryModel(name: 'United States of America', code: 'US');
final kDefaultCurrency = CurrencyModel(code: 'USD', name: 'USD', altcoin: true);

class MarketViewModel extends ViewModel
    with ErrorParseMixin, CountryInfoMixin, PaymentMethodsMixin
    implements WidgetsBindingObserver {
  MarketViewModel({
    required AdsRepository adsRepository,
    required PlacesSearch placesSearch,
    required AuthService authService,
    required AppStateV1 appState,
  })  : _placesSearch = placesSearch,
        _adsRepository = adsRepository,
        _authService = authService,
        _appState = appState;

  final AdsRepository _adsRepository;
  final PlacesSearch _placesSearch;
  final AuthService _authService;
  final AppStateV1 _appState;

  TextEditingController ctrlAmount = TextEditingController();
  TextEditingController ctrlLocation = TextEditingController();
  final indicatorKey = GlobalKey<RefreshIndicatorState>();

  final List<MapBoxPlace> _foundedPlaces = [];
  final List<CurrencyModel> currencies = [];

  late bool isGuestMode;

  final int _reloadCounter = 0;

  late Asset _asset;
  bool connection = true;
  final List<AdModel> ads = [];
  late CountryCodeModel countryCodeModel;
  late CountryModel selectedCountry;

  // String selectedLocation = '';
  OnlineProvider? selectedOnlineProvider = const OnlineProvider(url: '', code: '', name: '', currencies: []);
  final List<OnlineProvider> _countryPaymentMethods = [];
  late CurrencyModel selectedCurrency;
  late CurrencyModel defaultCurrency;
  bool hasMorePages = false;
  PaginationMeta? paginationMeta;
  late final GlobalKey<DropdownSearchState<dynamic>> onlineProviderDropdownKey;
  late final GlobalKey<DropdownSearchState<dynamic>> currencyDropdownKey;
  late final GlobalKey<DropdownSearchState<dynamic>> countryDropdownKey;
  late final StreamSubscription<bool> _subscriptionReload;
  late final StreamSubscription<bool> _countryChangedSignalSubscription;

  late TradeType _tradeType;
  double? _lon;
  double? _lat;

  List<String> tradeTypeMenu = [];
  List<String> assetMenu = [];
  bool _reloadPaymentMethods = true;
  bool displayFilterMessage = false;
  bool filterIsOpened = false;

  bool _loadingAds = false;
  bool initialLoading = true;
  bool _displayFilter = false;
  bool _amountInputValid = true;
  bool _loadingLocation = false;
  bool _displayClear = false;

  bool get displayClear => _displayClear;

  set displayClear(bool v) => updateWith(displayClear: v);

  bool get loadingLocation => _loadingLocation;

  set loadingLocation(bool v) => updateWith(loadingLocation: v);

  bool get amountInputValid => _amountInputValid;

  set amountInputValid(bool v) => updateWith(amountInputValid: v);

  bool get displayFilter => _displayFilter;

  set displayFilter(bool v) => updateWith(displayFilter: v);

  bool get loadingAds => _loadingAds;

  set loadingAds(bool v) => updateWith(loadingAds: v);

  Asset get asset => _asset;

  set asset(Asset? v) {
    if (v != null) AppSharedPrefs().setMarketSelectedAsset(v);
    updateWith(asset: v);
  }

  TradeType get tradeType => _tradeType;

  set tradeType(TradeType? v) {
    if (v != null) AppSharedPrefs().setMarketSelectedTradeType(v);
    updateWith(tradeType: v);
  }

  @override
  void init() async {
    _asset = AppSharedPrefs().marketSelectedAsset;
    _tradeType = AppSharedPrefs().marketSelectedTradeType;

    onlineProviderDropdownKey = GlobalKey<DropdownSearchState>();
    currencyDropdownKey = GlobalKey<DropdownSearchState>();
    countryDropdownKey = GlobalKey<DropdownSearchState>();
    //todo - refactor me (maybe with AutoRoute)
    isGuestMode = _authService.authState == AuthState.guest;
    _authService.onAuthStateChange.listen((e) {
      isGuestMode = e == AuthState.guest;
      notifyListeners();
    });

    _subscriptionReload = _appState.reloadMarket.listen((bool val) {
      if (val) {
        _reloadScreenWithDelay();
      }
    });
    initMenus();
    ctrlLocation.addListener(_locationListener);
    selectedCountry = CountryModel(name: getCountryName(_appState.countryCode), code: _appState.countryCode);
    final currencyCode = getCountryCurrencyCode(selectedCountry.code);
    if (currencyCode == 'EUR' && currencyCode != kAnyCountryCode) {
      selectedCountry = CountryModel(name: getCountryName(kAnyCountryCode), code: kAnyCountryCode);
    }
    selectedCurrency = CurrencyModel(code: currencyCode, name: currencyCode, altcoin: true);
    defaultCurrency = CurrencyModel(code: currencyCode, name: currencyCode, altcoin: true);
    await _loadCaches();

    _countryChangedSignalSubscription = _appState.countryChangedSignalController.stream.listen((val) {
      if (val) {
        changeSelectedCountryCodeAndCurrency(_appState.countryCode);
        indicatorKey.currentState?.show();
      }
    });

    super.init();
  }

  @override
  void onAfterBuild() async {
    if (!filterIsOpened) {
      indicatorKey.currentState?.show();
    }
  }

  Future _reloadScreenWithDelay() async {
    if (_reloadCounter < 3) {
      await Future.delayed(const Duration(seconds: 1));
      indicatorKey.currentState?.show();
    }
  }

  void initMenus() {
    tradeTypeMenu.addAll(TradeType.values.map((e) => e.translatedTitle(context).capitalize()).toList());
    assetMenu.addAll(Asset.values.map((e) => e.key()));
  }

  Future _loadCaches() async {
    await getCountries();
    await getCurrencies();
    await getCountryPaymentMethods(selectedCountry.code, context);
  }

  Future<List<CountryModel>> getCountries() async {
    _reloadPaymentMethods = true;
    final res = await _adsRepository.getCountries();
    if (res.isRight) {
      return {
        CountryModel(name: getCountryName(kAnyCountryCode), code: kAnyCountryCode),
        ...res.right,
      }.toList();
    } else {
      handleApiError(res.left, context);
      return [kDefaultCountry];
    }
  }

  void changeSelectedCurrency(CurrencyModel? val) {
    selectedCurrency = val ?? kDefaultCurrency;
    // if (selectedCurrency.code == 'EUR' &&
    //     selectedCountryCode != kAnyCountry &&
    //     !(tradeType != null && tradeType!.isLocal())) {
    //   changeSelectedCountryCode(kAnyCountry);
    // }
  }

  void changeSelectedCountryCodeAndCurrency(String? code) {
    selectedCountry = code != null ? CountryModel(name: getCountryName(code), code: code) : kDefaultCountry;
    String currencyCodeString = getCountryCurrencyCode(selectedCountry.code);
    defaultCurrency = selectedCurrency = currencies.firstWhere((e) => e.code == currencyCodeString);
    notifyListeners();
  }

  void changeSelectedCountryCode(String? code) {
    selectedCountry = code != null ? CountryModel(name: getCountryName(code), code: code) : kDefaultCountry;
    notifyListeners();
  }

  Future<List<CurrencyModel?>> getCurrenciesFromPaymentMethod() async {
    // _reloadPaymentMethods = true;
    if (selectedOnlineProvider?.code == null || selectedOnlineProvider?.code == kAnyPaymentMethodKey) {
      final res = await _adsRepository.getCurrencies();
      if (res.isRight) {
        defaultCurrency = selectedCurrency = res.right.firstWhere((e) => e.code == (selectedCurrency.code));
        notifyListeners();
        currencies.clear();
        currencies.addAll(res.right.where((e) => e.altcoin != true).toList());
        final List<CurrencyModel> resLst = [];
        for (final c in currencies) {
          if (resLst.firstWhereOrNull((val) => val.code == c.code) == null) {
            resLst.add(c);
          }
        }
        return resLst;
      } else {
        handleApiError(res.left, context);
        return [null];
      }
    } else {
      final currenciesLst = selectedOnlineProvider!.currencies;
      final String defaultCurrencyStr = currenciesLst[0];
      defaultCurrency =
          selectedCurrency = CurrencyModel(code: defaultCurrencyStr, name: defaultCurrencyStr, altcoin: true);
      notifyListeners();
      currencies.clear();
      currencies.addAll(currenciesLst.map((e) => CurrencyModel(code: e, name: e, altcoin: true)).toList());
      return currencies;
    }
  }

  Future<List<CurrencyModel?>> getCurrencies() async {
    _reloadPaymentMethods = true;
    final res = await _adsRepository.getCurrencies();
    if (res.isRight) {
      defaultCurrency = selectedCurrency = res.right.firstWhere((e) => e.code == (selectedCurrency.code));
      notifyListeners();
      currencies.clear();
      currencies.addAll(res.right.where((e) => e.altcoin != true).toList());
      return currencies;
    } else {
      handleApiError(res.left, context);
      return [null];
    }
  }

  void _locationListener() {
    if (ctrlLocation.text.length > 5) {
      displayClear = true;
    } else {
      displayClear = false;
    }
  }

  void locationFieldClear() {
    ctrlLocation.clear();
    _lon = _lat = null;
    notifyListeners();
  }

  Future<List<SearchItem>> findLocations() async {
    List<SearchItem> resStr = [];
    final List<MapBoxPlace>? res = await _placesSearch.getPlaces(ctrlLocation.text);
    if (res != null) {
      _foundedPlaces.clear();
      _foundedPlaces.addAll(res);
      resStr.addAll(res.map((e) => (SearchItem.fromPlace(e))).toList());
    }
    return resStr;
  }

  void addLocation(SearchItem searchItem) {
    _lon = searchItem.lon;
    _lat = searchItem.lat;
    selectedCountry = searchItem.countryCode != null
        ? CountryModel(name: getCountryName(searchItem.countryCode!), code: searchItem.countryCode!)
        : selectedCountry;
    ctrlLocation.text = searchItem.label;
    // getAds();
  }

  bool isLocalFilterReadyToSearch() {
    return _lat != null && _lon != null;
  }

  Future getAds({
    bool loadMore = false,
    bool reccursion = false,
    required BuildContext context,
  }) async {
    if (!loadingAds) {
      displayFilterMessage = false;
      loadingAds = true;
      initialLoading = false;

      String countryCodeForSearch = selectedCountry.code;
      if (tradeType.isLocal()) {
        if (ctrlLocation.text.isEmpty) {
          countryCodeForSearch = _appState.countryCode;
          late double lat;
          late double lon;
          try {
            lat = kCountriesCoordinates[countryCodeForSearch]!['latitude'] as double;
            lon = kCountriesCoordinates[countryCodeForSearch]!['longitude'] as double;
          } catch (e) {
            lat = 10.0;
            lon = 10.0;
          }
          _lat = lat;
          _lon = lon;
        } else {}
      }
      final res = await _adsRepository.publicAdSearch(
        asset: asset,
        tradeType: tradeType,
        currencyCode: selectedCurrency.code,
        countryCode: countryCodeForSearch,
        paymentMethod: selectedOnlineProvider?.url,
        amount: ctrlAmount.text,
        page: loadMore ? (paginationMeta?.currentPage ?? 0) + 1 : 0,
        lat: _lat,
        lon: _lon,
      );
      if (!loadMore) {
        ads.clear();
      }
      loadingAds = false;
      if (res.isRight) {
        paginationMeta = res.right.pagination;
        if (paginationMeta != null) {
          if (paginationMeta!.currentPage < paginationMeta!.totalPages) {
            hasMorePages = true;
          } else {
            hasMorePages = false;
          }
        }
        // remove dublicates and in case there was duplicates get ads again
        final List<AdModel> adsWithoutDuplicates = _removeDuplicates(res.right.data);
        // add ads
        ads.addAll(adsWithoutDuplicates);
        if (adsWithoutDuplicates.length < res.right.data.length) {
          if (!reccursion) {
            getAds(loadMore: true, reccursion: true, context: context);
          }
        }
      } else {
        handleApiError(res.left, context);
      }
      notifyListeners();
    }
  }

  List<AdModel> _removeDuplicates(List<AdModel> adsIn) {
    final List<AdModel> adsInForCompress = [...adsIn];
    final List<AdModel> adsInForIterate = [...adsIn];

    for (var val in ads) {
      final left = val;
      for (final right in adsInForIterate) {
        if (left.profile?.username == right.profile?.username &&
            left.tempPrice == right.tempPrice &&
            left.currency == right.currency &&
            left.onlineProvider == right.onlineProvider &&
            left.asset == right.asset &&
            left.tradeType == right.tradeType) {
          adsInForCompress.remove(right);
        }
      }
    }

    adsInForIterate.clear();
    adsInForIterate.addAll(adsInForCompress);

    final List<String> doNotRemoveIds = [];
    for (var val in adsInForIterate) {
      final left = val;
      for (final right in adsInForIterate) {
        if (left.id != right.id &&
            !doNotRemoveIds.contains(right.id) &&
            left.profile?.username == right.profile?.username &&
            left.tempPrice == right.tempPrice &&
            left.currency == right.currency &&
            left.onlineProvider == right.onlineProvider &&
            left.asset == right.asset &&
            left.tradeType == right.tradeType) {
          adsInForCompress.remove(right);
          doNotRemoveIds.add(left.id ?? '');
        }
      }
    }
    return adsInForCompress;
  }

  void changeOnlineProvider(OnlineProvider? val) {
    selectedOnlineProvider = val;
    if (worldwideMethods.contains(val?.code)) {
      changeSelectedCountryCode(kAnyCountryCode);
    }
    indicatorKey.currentState?.show();
  }

  void clearFilter() {
    selectedOnlineProvider = _countryPaymentMethods.first;
    onlineProviderDropdownKey.currentState?.changeSelectedItem(selectedOnlineProvider);
    ctrlAmount.clear();
    selectedCurrency = defaultCurrency;
    currencyDropdownKey.currentState?.changeSelectedItem(selectedCurrency);
    selectedCountry = CountryModel(name: getCountryName(_appState.countryCode), code: _appState.countryCode);
    countryDropdownKey.currentState?.changeSelectedItem(selectedCountry.code);
    locationFieldClear();
    notifyListeners();
  }

  Future<List<OnlineProvider>> getCountryPaymentMethods(String country, BuildContext context) async {
    if (_reloadPaymentMethods) {
      final res = await _adsRepository.getCountryPaymentMethods(country);
      if (res.isRight) {
        _countryPaymentMethods.clear();
        _countryPaymentMethods.add(
          OnlineProvider(
            url: '',
            code: kAnyPaymentMethodKey,
            name: context.intl.any_payment_method,
            currencies: [],
          ),
        );
        final List<OnlineProvider> resss22 = res.right;

        final paymentMethods = resss22.map((OnlineProvider e) {
          return localiseOnlineProvider(context, e);
        }).toList();
        paymentMethods.sort((a, b) => a.name.compareTo(b.name));
        _countryPaymentMethods.addAll(paymentMethods);
        selectedOnlineProvider = _countryPaymentMethods.first;
        _reloadPaymentMethods = false;
        notifyListeners();
        return _countryPaymentMethods;
      } else {
        handleApiError(res.left, context);
        return [];
      }
    }
    return _countryPaymentMethods;
  }

  void updateWith({
    Asset? asset,
    TradeType? tradeType,
    bool? loadingAds,
    bool? loadingSettings,
    bool? displayFilter,
    bool? amountInputValid,
    bool? loadingLocation,
    bool? displayClear,
  }) async {
    bool reloadAds = false;
    _loadingAds = loadingAds ?? _loadingAds;
    _displayClear = displayClear ?? _displayClear;
    if ((_asset != asset && asset != null || _tradeType != tradeType && tradeType != null) && !_loadingAds) {
      reloadAds = true;
    }
    _displayFilter = displayFilter ?? _displayFilter;
    if (tradeType != null && tradeType.isLocal()) {
      // reloadAds = false;
      // displayFilterMessage = true;
      ads.clear();
    }
    _asset = asset ?? _asset;
    _loadingLocation = loadingLocation ?? _loadingLocation;
    _tradeType = tradeType ?? _tradeType;
    _amountInputValid = amountInputValid ?? _amountInputValid;

    if (reloadAds) {
      reloadAds = false;
      indicatorKey.currentState?.show();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    ctrlAmount.dispose();
    ctrlLocation.dispose();
    _subscriptionReload.cancel();
    _countryChangedSignalSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    // TODO: implement didChangeAccessibilityFeatures
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      if (GetIt.I<AppParameters>().isCheckUpdates) {
        final newVersion = await AppUpdateService(
          appState: _appState,
        ).getReleaseVersion();
        if (newVersion != null) {
          await Future.delayed(const Duration(seconds: 1));
          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AppUpdateWidget(newVesrionNumber: newVersion);
              });
        }
      }
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // TODO: implement didChangeLocales
  }

  @override
  void didChangeMetrics() {
    // TODO: implement didChangeMetrics
  }

  @override
  void didChangePlatformBrightness() {
    // TODO: implement didChangePlatformBrightness
  }

  @override
  void didChangeTextScaleFactor() {
    // TODO: implement didChangeTextScaleFactor
  }

  @override
  void didHaveMemoryPressure() {
    // TODO: implement didHaveMemoryPressure
  }

  @override
  Future<bool> didPopRoute() {
    throw UnimplementedError();
  }

  @override
  Future<bool> didPushRoute(String route) {
    // TODO: implement didPushRoute
    throw UnimplementedError();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    // TODO: implement didPushRouteInformation
    throw UnimplementedError();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() {
    // TODO: implement didRequestAppExit
    throw UnimplementedError();
  }
}
