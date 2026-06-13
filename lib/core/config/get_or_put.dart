import 'package:get/get.dart';

T getOrPut<T>(T Function() builder, {String? tag, bool permanent = false}) {
  if (Get.isRegistered<T>(tag: tag)) {
    return Get.find<T>(tag: tag);
  } else {
    return Get.put<T>(builder(), tag: tag, permanent: permanent);
  }
}
