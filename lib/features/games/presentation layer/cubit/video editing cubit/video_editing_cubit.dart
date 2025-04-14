import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import '../../../../../core/utils/custom_snack_bar.dart';
import '../lineup drawing cubut/drawing__cubit.dart';
import '../lineup drawing cubut/drawing__state.dart';
import 'video_editing_state.dart';

class VideoEditingCubit extends Cubit<VideoEditingState> {
  final ImagePicker _picker = ImagePicker();
  static const MethodChannel _channel = MethodChannel('com.example.analysis_ai/recording');
  static const MethodChannel _gallerySaverChannel = MethodChannel('com.example.analysis_ai/gallery_saver');
  static const MethodChannel _mediaStoreChannel = MethodChannel('com.example.analysis_ai/mediastore');
  int? _lastTimestamp;
  bool _isStopping = false;

  VideoEditingCubit() : super(VideoEditingState());

  void updateControllerState() {
    final controller = state.controller;
    if (controller != null && controller.value.isPlaying) {
      emit(state.copyWith(isPlaying: true));
    } else {
      emit(state.copyWith(isPlaying: false));
    }
    final currentTimestamp = controller?.value.position.inMilliseconds ?? 0;
    _lastTimestamp = currentTimestamp;
  }

  Future<void> pickVideo() async {
    if (state.isPickerActive) return;
    emit(state.copyWith(isPickerActive: true));

    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) {
        emit(state.copyWith(isPickerActive: false));
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final persistentPath = '${tempDir.path}/picked_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(video.path).copy(persistentPath);

      final controller = VideoPlayerController.file(File(persistentPath));
      await controller.initialize();
      controller.addListener(updateControllerState);
      controller.play();

      emit(state.copyWith(
        controller: controller,
        originalVideoPath: persistentPath,
        isPlaying: true,
        isPickerActive: false,
        lines: [],
      ));
    } catch (e) {
      emit(state.copyWith(isPickerActive: false));
      print('Error picking video: $e');
    }
  }

  void togglePlayPause(BuildContext context, {GlobalKey? videoKey}) async {
    final controller = state.controller;
    if (controller == null) return;

    final currentTime = controller.value.position;

    if (controller.value.isPlaying) {
      controller.pause();
      String? imagePath;
      if (state.isRecording && videoKey != null) {
        imagePath = await _captureFrameWithDrawing(context, videoKey, currentTime.inMilliseconds);
      } else {
        imagePath = await _saveCurrentFrame(currentTime.inMilliseconds);
      }
      if (imagePath != null) {
        emit(state.copyWith(
          pauseStartTime: currentTime,
          playbackEvents: List.from(state.playbackEvents)
            ..add({'action': 'pause', 'timestamp': currentTime.inMilliseconds, 'imagePath': imagePath}),
        ));
      }
    } else {
      if (state.pauseStartTime != null) {
        final pauseDuration = currentTime - state.pauseStartTime!;
        emit(state.copyWith(
          pauseSegments: List.from(state.pauseSegments)
            ..add(PauseSegment(position: state.pauseStartTime!, duration: pauseDuration)),
          playbackEvents: List.from(state.playbackEvents)
            ..add({'action': 'play', 'timestamp': currentTime.inMilliseconds, 'pauseDuration': pauseDuration.inMilliseconds}),
          pauseStartTime: null,
        ));
      }
      controller.play();
    }
  }

  Future<String?> _saveCurrentFrame(int timestamp) async {
    try {
      if (state.controller == null || state.originalVideoPath == null) return null;
      final image = await VideoThumbnail.thumbnailData(
        video: state.originalVideoPath!,
        imageFormat: ImageFormat.PNG,
        quality: 100,
        timeMs: timestamp,
      );
      if (image == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pause_frame_$timestamp.png');
      await file.writeAsBytes(image);
      return file.path;
    } catch (e) {
      print('Error saving frame: $e');
      return null;
    }
  }

  Future<String?> _captureFrameWithDrawing(BuildContext context, GlobalKey videoKey, int timestamp) async {
    try {
      final boundary = videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/annotated_frame_$timestamp.png');
      await file.writeAsBytes(pngBytes);
      return file.path;
    } catch (e) {
      print('Error capturing annotated frame: $e');
      return null;
    }
  }

  void addDrawing(DrawingItem drawing, int timestamp) {
    final updatedLines = List<Map<String, dynamic>>.from(state.lines);
    updatedLines.add({'drawing': drawing, 'timestamp': timestamp});
    emit(state.copyWith(lines: updatedLines));
  }

  Future<void> startRecording(BuildContext context, Rect videoRect) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    bool hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      showErrorSnackBar(context, "Storage permission denied. Please grant permission in settings.");
      openAppSettings();
      return;
    }

    try {
      // Adjust top coordinate to account for 90.h padding
      final adjustedTop = videoRect.top + 90.h;
      print('Starting recording with rect: left=${videoRect.left}, top=$adjustedTop, width=${videoRect.width}, height=${videoRect.height}');
      await _channel.invokeMethod('startScreenRecording', {
        'left': videoRect.left.toInt(),
        'top': adjustedTop.toInt(),
        'width': videoRect.width.toInt(),
        'height': videoRect.height.toInt(),
      });
      emit(state.copyWith(
        isRecording: true,
        recordingStartTime: controller.value.position,
        playbackEvents: [],
        pauseSegments: [],
      ));
      controller.play();
    } catch (e) {
      print('Error starting recording: $e');
      showErrorSnackBar(context, "Failed to start recording: $e");
      emit(state.copyWith(isRecording: false));
    }
  }

  Future<String?> _cropVideo(String inputPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final croppedPath = '${dir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.mp4';
      // Crop top 60 pixels to exclude system red dot and status bar
      final command = '-i "$inputPath" -vf "crop=2*iw/3:ih-60:0:60" -c:a copy "$croppedPath"';
      print('FFmpeg command: $command');

      // Log input video info for debugging
      final infoSession = await FFmpegKit.execute('-i "$inputPath"');
      final infoLogs = await infoSession.getAllLogsAsString();
      print('Input video info: $infoLogs');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        print('Video cropped successfully: $croppedPath');
        if (File(croppedPath).existsSync()) {
          print('Cropped file verified, size: ${File(croppedPath).lengthSync()}');
          return croppedPath;
        } else {
          print('Cropped file does not exist: $croppedPath');
          return null;
        }
      } else {
        final logs = await session.getAllLogsAsString();
        print('FFmpeg error: $logs');
        return null;
      }
    } catch (e) {
      print('Error cropping video: $e');
      return null;
    }
  }

  Future<void> stopRecording(BuildContext context) async {
    final controller = state.controller;
    if (controller == null || !state.isRecording || _isStopping) return;

    _isStopping = true;
    print('Stopping recording...');

    String? outputPath;
    String? croppedPath;
    try {
      outputPath = await _channel.invokeMethod('stopScreenRecording');
      print('Received outputPath from platform: $outputPath');
      controller.pause();

      if (outputPath != null && File(outputPath).existsSync()) {
        print('Output file exists: $outputPath, size: ${File(outputPath).lengthSync()}');
        croppedPath = await _cropVideo(outputPath);
        if (croppedPath == null) {
          throw Exception("Failed to crop video");
        }
        print('Cropped file: $croppedPath, size: ${File(croppedPath).lengthSync()}');
        bool? saved = await _saveVideoToGallery(croppedPath, albumName: 'aiTacticals');
        print('Gallery save result: $saved');
        if (saved == true) {
          showSuccessSnackBar(context, "Video saved to gallery in aiTacticals album");
        } else {
          throw Exception("Failed to save video to gallery: saveVideo returned $saved");
        }
      } else {
        throw Exception("Recording output file not found or invalid: $outputPath");
      }
    } catch (e) {
      print('Error stopping recording: $e');
      showErrorSnackBar(context, "Failed to save recording: $e");
      rethrow;
    } finally {
      _isStopping = false;
      if (outputPath != null && File(outputPath).existsSync()) {
        print('Deleting temporary file: $outputPath');
        await File(outputPath).delete();
      }
      if (croppedPath != null && File(croppedPath).existsSync()) {
        print('Deleting temporary file: $croppedPath');
        await File(croppedPath).delete();
      }
      resetState();
      Navigator.of(context).pop();
    }
  }

  Future<bool?> _saveVideoToGallery(String path, {String? albumName}) async {
    if (path.isEmpty) {
      print('Error: Empty file path provided');
      throw ArgumentError('Please provide valid file path.');
    }
    final file = File(path);
    if (!file.existsSync()) {
      print('Error: File does not exist at path: $path');
      throw ArgumentError('File does not exist at path: $path');
    }
    print('Saving video to gallery: $path, size: ${file.lengthSync()}');

    try {
      print('Invoking saveVideo on channel com.example.analysis_ai/gallery_saver');
      bool? result = await _gallerySaverChannel.invokeMethod(
        'saveVideo',
        <String, dynamic>{
          'path': path,
          'albumName': albumName ?? 'aiTacticals',
          'toDcim': false,
        },
      );
      print('Gallery save result: $result');
      return result;
    } catch (e) {
      print('Error saving video to gallery via gallery_saver: $e');
      try {
        print('Falling back to mediastore channel');
        String fileName = path.split('/').last;
        String? savedPath = await _mediaStoreChannel.invokeMethod(
          'saveVideoToGallery',
          <String, dynamic>{
            'sourcePath': path,
            'fileName': fileName,
            'relativePath': albumName ?? 'aiTacticals',
          },
        );
        print('MediaStore save result: $savedPath');
        return savedPath != null;
      } catch (fallbackError) {
        print('Error saving video to gallery via mediastore: $fallbackError');
        rethrow;
      }
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final bool isAndroid13OrHigher = await _isAndroid13OrHigher();
      if (isAndroid13OrHigher) {
        var videoStatus = await Permission.videos.request();
        var micStatus = await Permission.microphone.request();
        print('Android 13+: Videos: $videoStatus, Microphone: $micStatus');
        if (!videoStatus.isGranted) {
          print('Video permission denied');
        }
        if (!micStatus.isGranted) {
          print('Microphone permission denied');
        }
        return videoStatus.isGranted && micStatus.isGranted;
      } else {
        var storageStatus = await Permission.storage.request();
        var micStatus = await Permission.microphone.request();
        print('Android < 13: Storage: $storageStatus, Microphone: $micStatus');
        if (!storageStatus.isGranted) {
          print('Storage permission denied');
        }
        if (!micStatus.isGranted) {
          print('Microphone permission denied');
        }
        return storageStatus.isGranted && micStatus.isGranted;
      }
    }
    return true;
  }

  Future<bool> _isAndroid13OrHigher() async {
    const platform = MethodChannel('com.example.analysis_ai/platform');
    try {
      final int sdkVersion = await platform.invokeMethod('getSdkVersion');
      return sdkVersion >= 33;
    } catch (e) {
      print('Error checking Android version: $e');
      return false;
    }
  }

  void resetState() {
    state.controller?.dispose();
    emit(VideoEditingState());
  }

  void seekBackward() {
    if (state.controller == null) return;
    final newPosition = (state.controller!.value.position.inMilliseconds - 10000)
        .clamp(0, state.controller!.value.duration.inMilliseconds);
    state.controller!.seekTo(Duration(milliseconds: newPosition));
  }

  void seekForward() {
    if (state.controller == null) return;
    final newPosition = (state.controller!.value.position.inMilliseconds + 10000)
        .clamp(0, state.controller!.value.duration.inMilliseconds);
    state.controller!.seekTo(Duration(milliseconds: newPosition));
  }

  void removeDrawingForTimestamp(DrawingItem drawing, int timestamp) {
    final updatedLines = List<Map<String, dynamic>>.from(state.lines)
      ..removeWhere((line) => line['timestamp'] == timestamp && line['drawing'] == drawing);
    emit(state.copyWith(lines: updatedLines));
  }
}