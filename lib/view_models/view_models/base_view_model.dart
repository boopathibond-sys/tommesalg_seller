import 'package:flutter/foundation.dart';

/// State a view-model can be in.
enum ViewState { idle, busy, success, error }

/// Common loading / error scaffolding for every ViewModel.
///
/// Subclasses just call [setState] / [setError] / [setSuccess] and the
/// view (via Provider/Consumer) rebuilds.
class BaseViewModel extends ChangeNotifier {
  ViewState _state = ViewState.idle;
  String?   _errorMessage;

  ViewState get state          => _state;
  String?   get errorMessage   => _errorMessage;
  bool      get isBusy         => _state == ViewState.busy;
  bool      get hasError       => _state == ViewState.error;

  void setState(ViewState newState) {
    _state = newState;
    notifyListeners();
  }

  void setError(String? message) {
    _errorMessage = message;
    _state = ViewState.error;
    notifyListeners();
  }

  void setSuccess() {
    _errorMessage = null;
    _state = ViewState.success;
    notifyListeners();
  }

  void resetState() {
    _errorMessage = null;
    _state = ViewState.idle;
    notifyListeners();
  }
}
