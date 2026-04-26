import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../models/plate_model.dart';

class PlateState {
  final List<Plate> plates;
  final bool isLoading;
  final String? error;

  const PlateState({this.plates = const [], this.isLoading = false, this.error});

  PlateState copyWith({List<Plate>? plates, bool? isLoading, String? error}) {
    return PlateState(
      plates: plates ?? this.plates,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PlateNotifier extends StateNotifier<PlateState> {
  final DioClient _dio;

  PlateNotifier(this._dio) : super(const PlateState());

  Future<void> fetchPlates() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _dio.getPlates();
      final data = res.data;
      if (data is Map && data['code'] == 200) {
        final list = (data['data'] as List?)?.map((e) => Plate.fromJson(e as Map<String, dynamic>)).toList() ?? [];
        state = state.copyWith(plates: list, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, error: data?['msg']?.toString() ?? 'Failed');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  String getPlateName(int id) {
    try {
      return state.plates.firstWhere((p) => p.id == id).name;
    } catch (_) {
      return 'Unknown';
    }
  }
}
