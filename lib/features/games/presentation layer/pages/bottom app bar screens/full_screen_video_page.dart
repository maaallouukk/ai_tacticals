import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../cubit/lineup drawing cubut/drawing__cubit.dart';
import '../../cubit/lineup drawing cubut/drawing__state.dart';
import '../../cubit/video editing cubit/video_editing_cubit.dart';
import '../../cubit/video editing cubit/video_editing_state.dart';
import '../../../../../core/utils/custom_snack_bar.dart';
import '../../../../../core/widgets/field_drawing_painter.dart';

class FullScreenVideoPage extends StatefulWidget {
  const FullScreenVideoPage({super.key});

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  final GlobalKey _videoKey = GlobalKey();
  final ValueNotifier<bool> _isDialOpen = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide status bar and navigation bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _isDialOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => DrawingCubit()),
      ],
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocBuilder<VideoEditingCubit, VideoEditingState>(
          builder: (context, videoState) {
            return BlocBuilder<DrawingCubit, DrawingState>(
              builder: (context, drawingState) {
                final videoWidth = 2 * MediaQuery.of(context).size.width / 3; // Left 2/3
                final videoHeight = MediaQuery.of(context).size.height;
                final currentTimestamp =
                    videoState.controller?.value.position.inMilliseconds ?? 0;

                final currentDrawings = videoState.lines
                    .where((line) => (line['timestamp'] as int) == currentTimestamp)
                    .map((line) => line['drawing'] as DrawingItem)
                    .toList();

                if (!videoState.isPlaying &&
                    !drawingState.isDrawing &&
                    drawingState.drawings != currentDrawings) {
                  context.read<DrawingCubit>().emit(drawingState.copyWith(
                    drawings: currentDrawings,
                    selectedDrawingIndex: null,
                  ));
                }

                final allDrawings = drawingState.isDrawing &&
                    drawingState.currentPoints.isNotEmpty
                    ? [
                  ...currentDrawings,
                  DrawingItem(
                    type: drawingState.currentMode,
                    points: drawingState.currentPoints,
                    color: drawingState.currentColor,
                  ),
                ]
                    : currentDrawings;

                return Row(
                  children: [
                    // Left: Video + Drawings (2/3 width)
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          SizedBox(height: 90.h), // Add top padding
                          Expanded(
                            child: GestureDetector(
                              onTapUp: (details) {
                                if (!drawingState.isDrawing &&
                                    drawingState.currentMode == DrawingMode.none &&
                                    !videoState.isPlaying) {
                                  final RenderBox? box = _videoKey.currentContext
                                      ?.findRenderObject() as RenderBox?;
                                  if (box != null) {
                                    final localPosition =
                                    box.globalToLocal(details.globalPosition);
                                    context
                                        .read<DrawingCubit>()
                                        .selectDrawing(localPosition);
                                  }
                                }
                              },
                              child: RawGestureDetector(
                                gestures: {
                                  PanGestureRecognizer:
                                  GestureRecognizerFactoryWithHandlers<
                                      PanGestureRecognizer>(
                                        () => PanGestureRecognizer(),
                                        (PanGestureRecognizer instance) {
                                      instance
                                        ..onStart = (details) {
                                          final RenderBox? box = _videoKey.currentContext
                                              ?.findRenderObject() as RenderBox?;
                                          if (box != null &&
                                              drawingState.currentMode !=
                                                  DrawingMode.none &&
                                              !videoState.isPlaying) {
                                            final localPosition = box
                                                .globalToLocal(details.globalPosition);
                                            context
                                                .read<DrawingCubit>()
                                                .startDrawing(localPosition);
                                          }
                                        }
                                        ..onUpdate = (details) {
                                          final RenderBox? box = _videoKey.currentContext
                                              ?.findRenderObject() as RenderBox?;
                                          if (box != null && !videoState.isPlaying) {
                                            final localPosition = box
                                                .globalToLocal(details.globalPosition);
                                            final drawingCubit =
                                            context.read<DrawingCubit>();
                                            if (drawingState.isDrawing &&
                                                drawingState.currentMode !=
                                                    DrawingMode.none) {
                                              drawingCubit.updateDrawing(
                                                localPosition,
                                                maxWidth: videoWidth,
                                                maxHeight: videoHeight,
                                              );
                                            } else if (drawingState
                                                .selectedDrawingIndex !=
                                                null &&
                                                drawingState.selectedDrawingIndex! <
                                                    drawingState.drawings.length) {
                                              drawingCubit.moveDrawing(
                                                details.delta,
                                                maxWidth: videoWidth,
                                                maxHeight: videoHeight,
                                              );
                                              final updatedLines = List<
                                                  Map<String, dynamic>>.from(
                                                  videoState.lines)
                                                ..removeWhere((line) =>
                                                (line['timestamp'] as int) ==
                                                    currentTimestamp);
                                              updatedLines.addAll(drawingCubit
                                                  .state.drawings
                                                  .map((drawing) => {
                                                'drawing': drawing,
                                                'timestamp': currentTimestamp,
                                              }));
                                              context
                                                  .read<VideoEditingCubit>()
                                                  .emit(videoState.copyWith(
                                                lines: updatedLines,
                                              ));
                                            }
                                          }
                                        }
                                        ..onEnd = (_) {
                                          if (drawingState.isDrawing &&
                                              drawingState.currentMode !=
                                                  DrawingMode.none &&
                                              !videoState.isPlaying) {
                                            final drawingCubit =
                                            context.read<DrawingCubit>();
                                            drawingCubit.endDrawing();
                                            final timestamp = videoState
                                                .controller?.value.position
                                                .inMilliseconds ??
                                                0;
                                            if (drawingCubit
                                                .state.drawings.isNotEmpty) {
                                              final newDrawing = drawingCubit
                                                  .state.drawings.last;
                                              context
                                                  .read<VideoEditingCubit>()
                                                  .addDrawing(newDrawing, timestamp);
                                              drawingCubit.emit(drawingCubit.state
                                                  .copyWith(
                                                currentPoints: [],
                                                isDrawing: false,
                                                currentMode: DrawingMode.none,
                                              ));
                                            }
                                          }
                                        };
                                    },
                                  ),
                                },
                                child: Stack(
                                  children: [
                                    RepaintBoundary(
                                      key: _videoKey,
                                      child: SizedBox(
                                        width: videoWidth,
                                        height: videoHeight - 90.h, // Adjust height
                                        child: videoState.controller != null &&
                                            videoState
                                                .controller!.value.isInitialized
                                            ? AspectRatio(
                                          aspectRatio: videoState
                                              .controller!.value.aspectRatio,
                                          child: Stack(
                                            children: [
                                              VideoPlayer(
                                                  videoState.controller!),
                                              CustomPaint(
                                                size: Size(
                                                    videoWidth, videoHeight),
                                                painter: FieldDrawingPainter(
                                                  allDrawings,
                                                  drawingState.currentPoints,
                                                  drawingState.currentMode,
                                                  drawingState.currentColor,
                                                  drawingState
                                                      .selectedDrawingIndex,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                            : const Center(
                                          child: Text(
                                            "Erreur: Vidéo non chargée",
                                            style: TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Recording indicator
                                    if (videoState.isRecording)
                                      Positioned(
                                        top: 10.h,
                                        left: 10.w,
                                        child: Container(
                                          width: 20.w,
                                          height: 20.w,
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.fiber_manual_record,
                                              color: Colors.white,
                                              size: 12.sp,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right: Controls (1/3 width)
                    Container(
                      width: 1.sw / 3,
                      color: Colors.black54,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(vertical: 20.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Back button
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              color: Colors.white,
                              iconSize: 30.sp,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            SizedBox(height: 20.h),
                            // Record button
                            _buildRecordButton(context, videoState),
                            SizedBox(height: 20.h),
                            // Stop button
                            _buildStopButton(context, videoState),
                            SizedBox(height: 20.h),
                            // Drawing options (SpeedDial)
                            _buildDrawingOptions(context, videoState, drawingState),
                            SizedBox(height: 20.h),
                            // Timeline
                            if (videoState.showTimeline &&
                                videoState.controller != null)
                              _buildTimeline(videoState),
                            SizedBox(height: 20.h),
                            // Video controls
                            _buildVideoControls(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecordButton(BuildContext context, VideoEditingState videoState) {
    return SizedBox(
      height: 60.w,
      width: 60.w,
      child: FloatingActionButton(
        heroTag: 'record_button',
        onPressed: videoState.controller != null && !videoState.isRecording
            ? () async {
          final renderBox = _videoKey.currentContext?.findRenderObject()
          as RenderBox?;
          if (renderBox != null) {
            final videoPosition = renderBox.localToGlobal(Offset.zero);
            final videoSize = renderBox.size;
            await context.read<VideoEditingCubit>().startRecording(
              context,
              Rect.fromLTWH(
                videoPosition.dx,
                videoPosition.dy,
                videoSize.width,
                videoSize.height,
              ),
            );
          }
        }
            : null,
        child: const Icon(Icons.fiber_manual_record, color: Colors.black),
        backgroundColor: Colors.lightGreen,
      ),
    );
  }

  Widget _buildStopButton(BuildContext context, VideoEditingState videoState) {
    return SizedBox(
      height: 60.w,
      width: 60.w,
      child: FloatingActionButton(
        heroTag: 'stop_button',
        onPressed: videoState.controller != null && videoState.isRecording
            ? () => context.read<VideoEditingCubit>().stopRecording(context)
            : null,
        child: const Icon(Icons.stop),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Widget _buildDrawingOptions(
      BuildContext context, VideoEditingState videoState, DrawingState drawingState) {
    final drawingCubit = context.read<DrawingCubit>();
    final videoCubit = context.read<VideoEditingCubit>();
    final currentTimestamp =
        videoCubit.state.controller?.value.position.inMilliseconds ?? 0;

    return ValueListenableBuilder<bool>(
      valueListenable: _isDialOpen,
      builder: (context, isOpen, child) {
        return SpeedDial(
          openCloseDial: _isDialOpen,
          icon: drawingState.isDrawing ? Icons.stop : Icons.edit,
          activeIcon: Icons.close,
          backgroundColor: Colors.lightBlue,
          foregroundColor: Colors.white,
          buttonSize: Size(60.w, 60.w),
          childPadding: EdgeInsets.symmetric(vertical: 10.h),
          spaceBetweenChildren: 10.h,
          onOpen: () {
            _isDialOpen.value = true;
          },
          onClose: () {
            _isDialOpen.value = false;
          },
          children: [
            SpeedDialChild(
              child: const Icon(Icons.brush),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Draw',
              onTap: () {
                drawingCubit.setDrawingMode(DrawingMode.free);
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.circle_outlined),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Circle',
              onTap: () {
                drawingCubit.setDrawingMode(DrawingMode.circle);
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.person),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Player',
              onTap: () {
                drawingCubit.setDrawingMode(DrawingMode.player);
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.arrow_forward),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Arrow',
              onTap: () {
                drawingCubit.setDrawingMode(DrawingMode.arrow);
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.color_lens),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Color',
              onTap: () {
                _showColorPicker(context, drawingCubit);
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.undo),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Undo',
              onTap: () {
                if (drawingState.drawings.isNotEmpty) {
                  drawingCubit.undoDrawingForFrame(
                    currentTimestamp,
                    videoState.lines,
                    videoCubit.removeDrawingForTimestamp,
                  );
                }
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.redo),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Redo',
              onTap: () {
                if (drawingState.redoStack.isNotEmpty) {
                  drawingCubit.redoDrawingForFrame(
                    currentTimestamp,
                    videoCubit.addDrawing,
                  );
                }
                _isDialOpen.value = false;
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.clear),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              label: 'Clear',
              onTap: () {
                if (drawingState.drawings.isNotEmpty) {
                  drawingCubit.clearDrawings();
                }
                _isDialOpen.value = false;
              },
            ),
          ],
          onPress: () {
            if (videoCubit.state.isPlaying) {
              showErrorSnackBar(context,
                  "Cannot draw while the video is playing. Please pause the video first.");
              return;
            }
            if (drawingState.isDrawing) {
              drawingCubit.endDrawing();
              final timestamp =
                  videoCubit.state.controller?.value.position.inMilliseconds ?? 0;
              if (drawingState.drawings.isNotEmpty) {
                videoCubit.addDrawing(drawingState.drawings.last, timestamp);
                drawingCubit.emit(drawingCubit.state.copyWith(
                  currentPoints: [],
                  isDrawing: false,
                  currentMode: DrawingMode.none,
                ));
              }
              _isDialOpen.value = false;
            } else {
              _isDialOpen.value = !_isDialOpen.value;
            }
          },
        );
      },
    );
  }

  Widget _buildTimeline(VideoEditingState state) {
    return Container(
      width: 1.sw / 3 - 20.w,
      color: Colors.black54,
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: state.controller!.value.position.inSeconds.toDouble(),
            min: 0,
            max: state.controller!.value.duration.inSeconds.toDouble(),
            onChanged: (value) {
              state.controller!.seekTo(Duration(seconds: value.toInt()));
              context.read<DrawingCubit>().emit(context.read<DrawingCubit>().state.copyWith(
                currentPoints: [],
                isDrawing: false,
                currentMode: DrawingMode.none,
              ));
            },
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(state.controller!.value.position),
                  style: TextStyle(color: Colors.white, fontSize: 12.sp),
                ),
                Text(
                  _formatDuration(state.controller!.value.duration),
                  style: TextStyle(color: Colors.white, fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoControls() {
    return BlocBuilder<VideoEditingCubit, VideoEditingState>(
      builder: (context, state) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.replay_10, color: Colors.white, size: 25.sp),
            onPressed: state.controller != null
                ? () {
              context.read<VideoEditingCubit>().seekBackward();
              context.read<DrawingCubit>().emit(context.read<DrawingCubit>().state.copyWith(
                currentPoints: [],
                isDrawing: false,
                currentMode: DrawingMode.none,
              ));
            }
                : null,
          ),
          IconButton(
            icon: Icon(
              state.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 25.sp,
            ),
            onPressed: state.controller != null
                ? () {
              context
                  .read<VideoEditingCubit>()
                  .togglePlayPause(context, videoKey: _videoKey);
              if (state.isPlaying) {
                context
                    .read<DrawingCubit>()
                    .emit(context.read<DrawingCubit>().state.copyWith(
                  currentPoints: [],
                  isDrawing: false,
                  currentMode: DrawingMode.none,
                ));
              }
            }
                : null,
          ),
          IconButton(
            icon: Icon(Icons.forward_10, color: Colors.white, size: 25.sp),
            onPressed: state.controller != null
                ? () {
              context.read<VideoEditingCubit>().seekForward();
              context.read<DrawingCubit>().emit(context.read<DrawingCubit>().state.copyWith(
                currentPoints: [],
                isDrawing: false,
                currentMode: DrawingMode.none,
              ));
            }
                : null,
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, DrawingCubit cubit) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: cubit.state.currentColor,
            onColorChanged: (color) {
              cubit.changeColor(color);
            },
            showLabel: true,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
}