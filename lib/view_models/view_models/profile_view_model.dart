import '../../core/services/profile_service.dart';
import '../../models/seller_profile.dart';
import 'base_view_model.dart';

class ProfileViewModel extends BaseViewModel {
  final _service = ProfileService.instance;

  SellerProfile? get profile => _service.profile;

  Future<void> loadProfile() async {
    setState(ViewState.busy);
    try {
      await _service.fetchProfile();
      setSuccess();
    } catch (e) {
      setError(e.toString());
    }
  }
}
