import '../../models/seller_profile.dart';
import '../config/env_config.dart';
import 'api_client.dart';
import 'auth_service.dart';

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  final _api = ApiClient.instance;

  SellerProfile? _profile;
  SellerProfile? get profile => _profile;

  Future<SellerProfile> fetchProfile() async {
    final response = await _api.post(
      '${EnvConfig.baseUrl}/api/v1/seller/profile',
      headers: AuthService.instance.authHeaders,
    );

    if (!response.isSuccess) {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }

    final data = response.json;
    _profile = SellerProfile.fromJson(data['data'] as Map<String, dynamic>);
    return _profile!;
  }
}
