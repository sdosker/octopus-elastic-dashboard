// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:dot_cast/dot_cast.dart';
import 'package:patterns_canvas/patterns_canvas.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, degrees, radians;

import 'package:elastic_dashboard/services/nt4_client.dart';
import 'package:elastic_dashboard/services/struct_schemas/pose2d_struct.dart';
import 'package:elastic_dashboard/util/test_utils.dart';
import 'package:elastic_dashboard/widgets/nt_widgets/multi_topic/field_widget/field_model.dart';
import 'package:elastic_dashboard/widgets/nt_widgets/multi_topic/field_widget/field_painters.dart';
import 'package:elastic_dashboard/widgets/nt_widgets/nt_widget.dart';

// ignore: unused_import

// import 'package:elastic_dashboard/services/log.dart';

// ignore: unused_import

extension _SizeUtils on Size {
  Offset get toOffset => Offset(width, height);

  Size rotateBy(double angle) => Size(
    (width * cos(angle) - height * sin(angle)).abs(),
    (height * cos(angle) + width * sin(angle)).abs(),
  );
}

String formatDouble(double value, int fractionDigits, int decimalDigits) {
  int add = 0;
  double fakeval = value;
  bool negative = false;
  if (value < 0) //negative value
  {
    if (fakeval > -1) fakeval -= 1;
    negative = true;
    while (fakeval > -pow(10, decimalDigits - 1)) {
      fakeval *= 10;
      add++;
    }
  } else if (value > 0) //positive value
  {
    if (fakeval < 1) fakeval += 1;
    while (fakeval < pow(10, decimalDigits - 1)) {
      fakeval *= 10;
      add++;
    }
  }
  String output = value.abs().toStringAsFixed(fractionDigits);
  while (add > 0) {
    output = '0$output';
    add--;
  }
  output = negative ? '-$output' : ' $output';
  return output;
}

Offset pose = Offset.zero;

class FieldWidget extends NTWidget {
  static const String widgetType = 'Field';

  const FieldWidget({super.key});

  Offset _getTrajectoryPointOffset(
    FieldWidgetModel model, {
    required double x,
    required double y,
    required Offset fieldCenter,
    required double scaleReduction,
  }) {
    if (!x.isFinite) {
      x = 0;
    }
    if (!y.isFinite) {
      y = 0;
    }
    double xFromCenter =
        (x * model.field.pixelsPerMeterHorizontal - fieldCenter.dx) *
        scaleReduction;

    double yFromCenter =
        (fieldCenter.dy - (y * model.field.pixelsPerMeterVertical)) *
        scaleReduction;

    return Offset(xFromCenter, yFromCenter);
  }

  static const int ENABLED_FLAG = 0x01;
  static const int AUTO_FLAG = 0x02;
  static const int TEST_FLAG = 0x04;
  static const int EMERGENCY_STOP_FLAG = 0x08;
  static const int FMS_ATTACHED_FLAG = 0x10;
  static const int DS_ATTACHED_FLAG = 0x20;

  String _getMatchTypeString(int matchType) {
    switch (matchType) {
      case 1:
        return 'Practice';
      case 2:
        return 'Qualification';
      case 3:
        return 'Elimination';
      default:
        return 'Unknown';
    }
  }

  bool emptyString(String string) =>
      (string.isEmpty || string == '' || string == ' ');

  bool _flagMatches(int word, int flag) => (word & flag) != 0;

  @override
  Widget build(BuildContext context) {
    FieldWidgetModel model = cast(context.watch<NTWidgetModel>());

    return LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: Listenable.merge(model.subscriptions),
        child: model.field.fieldImage,
        builder: (context, child) {
          List<Object?> robotPositionRaw = [
            // model.robotXSubscription.value,
            // model.robotYSubscription.value,
            // model.robotHeadingSubscription.value,
            model.robotSubscription.value,
          ];
          String eventName = tryCast(model.eventNameSubscription.value) ?? '';
          int controlData = tryCast(model.controlDataSubscription.value) ?? 32;
          bool redAlliance = tryCast(model.allianceTopic.value) ?? true;
          String gameMessage(bool upper) {
            String message =
                tryCast(model.gameSpecificMessageSubscription.value) ??
                (redAlliance ? 'r' : 'b');
            if (message == ' ' || emptyString(message)) {
              message = redAlliance ? 'b' : 'r';
            }
            return upper ? message.toUpperCase() : message;
          }

          // String gameMessage =
          //     tryCast(model.gameSpecificMessageSubscription.value) ??
          //     (redAlliance ? 'r' : 'b');
          int matchNumber = tryCast(model.matchNumberSubscription.value) ?? 0;
          int matchType = tryCast(model.matchTypeSubscription.value) ?? 0;
          int replayNumber = tryCast(model.replayNumberSubscription.value) ?? 0;

          bool hubEnabled =
              tryCast(model.hubEnabledSubscription.value) ?? false;
          double shiftTimerNumber() {
            double val = tryCast(model.shiftTimerSubscription.value) ?? 0;
            if (val < 0) val += 150;
            return val;
          }

          double currentShiftNumber =
              tryCast(model.currentShiftSubscription.value) ??
              0; //tryCast(model.currentShiftSubscription.value) ?? 0;
          bool bothHubEnabled =
              (currentShiftNumber <= 2 || currentShiftNumber == 7);
          bool
          flashHub() => /*((shiftTimerNumber <= 0 ? shiftTimerNumber+150 : shiftTimerNumber)*/
              (shiftTimerNumber() * 10 % 2) > 0.6;
          bool wontBeDisabled(bool enemy) {
            // true if the next shift doesn't mean a disable of this hub
            if (currentShiftNumber == 1 || currentShiftNumber == 6) {
              return true; //both will still be enabled next shift
            }
            bool first = (currentShiftNumber == 2 || currentShiftNumber == 4);
            bool seccond = (currentShiftNumber == 3 || currentShiftNumber == 5);
            bool alliance = enemy ? redAlliance : !redAlliance;
            if (alliance) //red
            {
              if (gameMessage(true).contains('B') &&
                  first) //Blue will be disabled first, so we stay on shift 1, 3
              {
                return true;
              } else if (gameMessage(true).contains('R') &&
                  seccond) //red will be disabled first, so we stay on shift 2, 4]
              {
                return true;
              }
            } else if (!alliance) //blue
            {
              if (gameMessage(true).contains('R') &&
                  first) //Red will be disabled first, so we stay on shift 1, 3
              {
                return true;
              } else if (gameMessage(true).contains('B') &&
                  seccond) //Blue will be disabled first, so we stay on shift 2, 4]
              {
                return true;
              }
            }
            return false;
          }

          String eventNameDisplay = '$eventName${(eventName != '') ? ' ' : ''}';
          String matchTypeString = _getMatchTypeString(matchType);
          String replayNumberDisplay = (replayNumber != 0)
              ? ' (replay $replayNumber)'
              : '';

          bool fmsConnected = _flagMatches(controlData, FMS_ATTACHED_FLAG);
          bool dsAttached = _flagMatches(controlData, DS_ATTACHED_FLAG);

          bool emergencyStopped = _flagMatches(
            controlData,
            EMERGENCY_STOP_FLAG,
          );

          Color robotcontrolstateColor = Color.fromARGB(255, 255, 0, 0);
          String robotControlState = 'Disabled';
          if (_flagMatches(controlData, ENABLED_FLAG)) {
            if (_flagMatches(controlData, TEST_FLAG)) {
              robotcontrolstateColor = Color.fromARGB(255, 0, 100, 0);
              robotControlState = 'Test';
            } else if (_flagMatches(controlData, AUTO_FLAG)) {
              robotcontrolstateColor = Color.fromARGB(255, 100, 100, 0);
              robotControlState = 'Autonomous';
            } else {
              robotcontrolstateColor = Color.fromARGB(255, 0, 100, 100);
              robotControlState = 'Teleoperated';
            }
          }

          String matchDisplayString =
              '$eventNameDisplay$matchTypeString match $matchNumber$replayNumberDisplay';
          Widget matchDisplayWidget =
              // Row(
              // //mainAxisSize: MainAxisSize.min,
              // children: [
              Container(
                // alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: (!redAlliance)
                      ? Colors.red.shade900
                      : Colors.blue.shade900,
                  borderRadius: BorderRadius.circular(5.0),
                ),
                child: Text(
                  matchDisplayString,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                // ),
                // ],
              );

          String fmsDisplayString = (fmsConnected) ? 'FMS ☑' : 'FMS ☐';
          String dsDisplayString = (dsAttached) ? 'DS   ☑' : 'DS   ☐';

          Icon fmsDisplayIcon = (fmsConnected)
              ? const Icon(Icons.check, color: Colors.green, size: 18)
              : const Icon(Icons.clear, color: Colors.red, size: 18);
          Icon dsDisplayIcon = (dsAttached)
              ? const Icon(Icons.check, color: Colors.green, size: 18)
              : const Icon(Icons.clear, color: Colors.red, size: 18);

          late Widget robotStateWidget;
          if (emergencyStopped) {
            robotStateWidget = Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  flex: 25,
                  child: CustomPaint(
                    size: const Size(80, 15),
                    painter: _BlackAndYellowStripes(),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 0, 0, 0),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    'EMERGENCY STOPPED',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Expanded(
                  flex: 25,
                  child: CustomPaint(
                    size: const Size(80, 15),
                    painter: _BlackAndYellowStripes(),
                  ),
                ),
              ],
            );
          } else {
            robotStateWidget = Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 107, 3, 93),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Row(
                    children: [
                      Text('Robot State: '),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color:
                              robotcontrolstateColor, //const Color.fromARGB(255, 3, 107, 76),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(robotControlState),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // return Column(
          //   children: [
          //     matchDisplayWidget,
          //     const Spacer(flex: 2),
          //     // DS and FMS connected
          //     Row(
          //       children: [
          //         const Spacer(),
          //         Row(
          //           children: [
          //             fmsDisplayIcon,
          //             const SizedBox(width: 5),
          //             Text(fmsDisplayString),
          //           ],
          //         ),
          //         const Spacer(),
          //         Row(
          //           children: [
          //             dsDisplayIcon,
          //             const SizedBox(width: 5),
          //             Text(dsDisplayString),
          //           ],
          //         ),
          //         const Spacer(),
          //       ],
          //     ),
          //     const Spacer(),
          //     // Robot State
          //     robotStateWidget,
          //   ],
          // );

          double robotX = 0;
          double robotY = 0;
          double robotTheta = 0;

          if (model.isPoseStruct(model.robotTopicName)) {
            List<int> poseBytes = robotPositionRaw.whereType<int>().toList();
            Pose2dStruct poseStruct = Pose2dStruct.valueFromBytes(
              Uint8List.fromList(poseBytes),
            );

            robotX = poseStruct.x;
            robotY = poseStruct.y;
            robotTheta = poseStruct.angle;
          } else {
            List<double> robotPosition = robotPositionRaw
                .whereType<double>()
                .toList();
            if (robotPosition.isEmpty ||
                (robotPosition[0] == 0 &&
                    robotPosition[1] == 0 &&
                    robotPosition[2] == 0)) {
              robotPosition =
                  (robotPositionRaw.first as List<Object?>?)
                      ?.whereType<double>()
                      .toList() ??
                  [];
              // logger.debug('Something went wrong with the PoseStruct, falling back from: $robotPositionRaw to $robotPosition');
              //logger.debug('Value: ${model.visionTopics.targetPose} + ${Offset(robotPosition[0],robotPosition[1])} = ${Offset(model.visionTopics.targetPose.dx+robotPosition[0],-model.visionTopics.targetPose.dy+robotPosition[1])}');
            }
            //logger.debug('shift: $currentShiftNumber & timer: ${shiftTimerNumber()} & debug: ${model.currentShiftSubscription.value}');

            if (robotPosition.length >= 3) {
              robotX = robotPosition[0];
              robotY = robotPosition[1];
              robotTheta = radians(robotPosition[2]);
            }
          }

          // List<Object?> robotVisionPositionRaw = [
          //   // model.robotXSubscription.value,
          //   // model.robotYSubscription.value,
          //   // model.robotHeadingSubscription.value,
          //   model.visionTopics._target_pose
          // ];

          // double robotVisionX = 0;
          // double robotVisionY = 0;
          // double robotVisionTheta = 0;

          // {
          //   List<double> robotVisionPosition = robotVisionPositionRaw
          //       .whereType<double>()
          //       .toList();
          //   if (robotVisionPosition.isEmpty || (robotVisionPosition[0] == 0 && robotVisionPosition[1] == 0 && robotVisionPosition[2] == 0)) {
          //     robotVisionPosition = (robotVisionPositionRaw.first as List<Object?>?)
          //       ?.whereType<double>()
          //       .toList() ?? [];
          //      logger.debug('Something went wrong with the PoseStruct, falling back from: $robotVisionPositionRaw to $robotVisionPosition');
          //     //logger.debug('Value: ${model.visionTopics.targetPose.}');//não achei outro canto pra debug

          //   }

          //   if (robotVisionPosition.length >= 3) {
          //     robotVisionX = robotVisionPosition[0];
          //     robotVisionY = robotVisionPosition[1];
          //     robotVisionTheta = radians(robotVisionPosition[5]);//roll, pitch, yaw
          //   }
          // }

          //debug output the values from robotxy and theta
          // debugPrint('robotPositionRaw: $robotPositionRaw');
          // debugPrint('robotX: $robotX, robotY: $robotY, robotTheta: $robotTheta');
          // debugPrint('model.robotSubscription.value: ${model.robotSubscription.value}');

          Size size = Size(constraints.maxWidth, constraints.maxHeight);

          model.widgetSize = size;

          final imageSize = model.field.fieldImageSize ?? const Size(0, 0);

          double rotation = -radians(model.fieldRotation);

          final rotatedImageBoundingBox = imageSize.rotateBy(rotation);

          double scale = 1.0;

          if (rotatedImageBoundingBox.width > 0) {
            scale = size.width / rotatedImageBoundingBox.width;
          }

          if (rotatedImageBoundingBox.height > 0) {
            scale = min(scale, size.height / rotatedImageBoundingBox.height);
          }

          if (scale.isNaN) {
            scale = 0;
          }

          Size imageDisplaySize = imageSize * scale;

          Offset fieldCenter = model.field.center;

          if (!model.rendered &&
              model.widgetSize != null &&
              size != const Size(0, 0) &&
              size.width > 100.0 &&
              scale != 0.0 &&
              fieldCenter != const Offset(0.0, 0.0) &&
              model.field.fieldImageLoaded) {
            model.rendered = true;
          }

          if (!model.rendered && !isUnitTest) {
            Future.delayed(const Duration(milliseconds: 100), model.refresh);
          }

          List<List<Offset>> trajectoryPoints = [];
          if (model.showTrajectories) {
            for (NT4Subscription objectSubscription
                in model.otherObjectSubscriptions) {
              List<Object?>? objectPositionRaw = objectSubscription.value
                  ?.tryCast<List<Object?>>();

              if (objectPositionRaw == null) {
                continue;
              }

              bool isTrajectory = objectSubscription.topic
                  .toLowerCase()
                  .endsWith('trajectory');

              bool isStructArray = model.isPoseArrayStruct(
                objectSubscription.topic,
              );
              bool isStructObject =
                  model.isPoseStruct(objectSubscription.topic) || isStructArray;

              if (isStructObject) {
                isTrajectory =
                    isTrajectory ||
                    (isStructArray &&
                        objectPositionRaw.length ~/ Pose2dStruct.length > 8);
              } else {
                isTrajectory = isTrajectory || objectPositionRaw.length > 24;
              }

              if (!isTrajectory) {
                continue;
              }

              List<Offset> objectTrajectory = [];

              if (isStructObject) {
                List<int> structArrayBytes = objectPositionRaw
                    .whereType<int>()
                    .toList();
                List<Pose2dStruct> poseArray = Pose2dStruct.listFromBytes(
                  Uint8List.fromList(structArrayBytes),
                );
                for (Pose2dStruct pose in poseArray) {
                  objectTrajectory.add(
                    _getTrajectoryPointOffset(
                      model,
                      x: pose.x,
                      y: pose.y,
                      fieldCenter: fieldCenter,
                      scaleReduction: scale,
                    ),
                    // builder: (context, constraints) {
                    //   Size size = Size(constraints.maxWidth, constraints.maxHeight);
                    //   FittedSizes fittedSizes = applyBoxFit(
                    //     BoxFit.contain,
                    //     model.field.fieldImageSize ?? const Size(0, 0),
                    //     size,
                    //   );
                    //   FittedSizes rotatedFittedSizes = applyBoxFit(
                    //     BoxFit.contain,
                    //     model.field.fieldImageSize?.rotateBy(
                    //           -radians(model.fieldRotation),
                    //         ) ??
                    //         const Size(0, 0),
                    //     size,
                    //   );
                    //   double scaleReduction =
                    //       (fittedSizes.destination.width / fittedSizes.source.width);
                    //   double rotatedScaleReduction =
                    //       (rotatedFittedSizes.destination.width /
                    //       rotatedFittedSizes.source.width);

                    //   if (scaleReduction.isNaN) {
                    //     scaleReduction = 0;
                    //   }
                    //   if (rotatedScaleReduction.isNaN) {
                    //     rotatedScaleReduction = 0;
                    //   }

                    //   Offset fittedCenter = fittedSizes.destination.toOffset / 2;
                    //   Offset fieldCenter = model.field.center;

                    //   model.widgetSize = size;

                    //   if (!model.rendered &&
                    //       model.widgetSize != null &&
                    //       size != const Size(0, 0) &&
                    //       size.width > 100.0 &&
                    //       scaleReduction != 0.0 &&
                    //       fieldCenter != const Offset(0.0, 0.0) &&
                    //       model.field.fieldImageLoaded) {
                    //     model.rendered = true;
                    //   }

                    //   // Try rebuilding again if the image isn't fully rendered
                    //   // Can't do it if it's in a unit test cause it causes issues with timers running
                    //   if (!model.rendered && !isUnitTest) {
                    //     Future.delayed(
                    //       const Duration(milliseconds: 100),
                    //       model.refresh,
                    //     );
                    //   }

                    //   return Stack(
                    //     children: [
                    //       // Pannable field widget
                    //       InteractiveViewer(
                    //         transformationController: model.transformController,
                    //         constrained: true,
                    //         maxScale: 2,
                    //         minScale: 1,
                    //         panAxis: PanAxis.free,
                    //         clipBehavior: Clip.hardEdge,
                    //         trackpadScrollCausesScale: true,
                    //         child: ListenableBuilder(
                    //           listenable: Listenable.merge(listeners),
                    //           builder: (context, child) {
                    //             List<List<Offset>> trajectoryPoints = _getTrajectoryPoints(
                    //               model: model,
                    //               fieldCenter: fieldCenter,
                    //               scaleReduction: scaleReduction,
                    //             );

                    //             List<Widget> otherObjects = _getOtherObjectWidgets(
                    //               model: model,
                    //               fieldCenter: fieldCenter,
                    //               scaleReduction: scaleReduction,
                    //             );

                    //             return Transform.scale(
                    //               scale: rotatedScaleReduction / scaleReduction,
                    //               child: Transform.rotate(
                    //                 angle: radians(model.fieldRotation),
                    //                 child: Stack(
                    //                   alignment: Alignment.center,
                    //                   children: [
                    //                     SizedBox(
                    //                       height: constraints.maxHeight,
                    //                       width: constraints.maxWidth,
                    //                       child: model.field.fieldImage,
                    //                     ),
                    //                     for (List<Offset> points in trajectoryPoints)
                    //                       CustomPaint(
                    //                         size: fittedSizes.destination,
                    //                         painter: TrajectoryPainter(
                    //                           center: fittedCenter,
                    //                           color: model.trajectoryColor,
                    //                           points: points,
                    //                           strokeWidth:
                    //                               model.trajectoryPointSize *
                    //                               model.field.pixelsPerMeterHorizontal *
                    //                               scaleReduction,
                    //                         ),
                    //                       ),
                    //                     ...otherObjects,
                    //                   ],
                    //                 ),
                    //               ),
                    //             );
                    //           },
                    //         ),
                    //       ),
                    //       // Robot, trajectories overlay
                    //       IgnorePointer(
                    //         ignoring: true,
                    //         child: InteractiveViewer(
                    //           transformationController: model.transformController,
                    //           clipBehavior: Clip.none,
                    //           child: ListenableBuilder(
                    //             listenable: Listenable.merge([
                    //               ...listeners,
                    //               model.transformController,
                    //             ]),
                    //             builder: (context, child) => _buildRobotOverlay(
                    //               model: model,
                    //               size: size,
                    //               scaleReduction: scaleReduction,
                    //               fieldCenter: fieldCenter,
                    //               rotatedScaleReduction: rotatedScaleReduction,
                    //               constraints: constraints,
                    //               fittedSizes: fittedSizes,
                    //               fittedCenter: fittedCenter,
                    //               controller: model.transformController,
                    //             ),
                    //           ),
                    //         ),
                    //       ),
                    //     ],
                    //   );
                    // },
                  );
                }
              } else {
                List<double> objectPosition = objectPositionRaw
                    .whereType<double>()
                    .toList();
                for (int i = 0; i < objectPosition.length - 2; i += 3) {
                  objectTrajectory.add(
                    _getTrajectoryPointOffset(
                      model,
                      x: objectPosition[i],
                      y: objectPosition[i + 1],
                      fieldCenter: fieldCenter,
                      scaleReduction: scale,
                    ),
                  );
                }
              }
              if (objectTrajectory.isNotEmpty) {
                trajectoryPoints.add(objectTrajectory);
              }
            }
          }

          final finalSize = rotatedImageBoundingBox * scale;

          return GestureDetector(
            onTapDown: (details) {
              if (model.ntConnection.isNT4Connected) {
                // The tap details are in the coordinate space of the GestureDetector,
                // which is the size of the whole widget. We need to translate
                // this to the coordinate space of the field itself.
                final tapInWidget = details.localPosition;

                // The field is centered in the widget, so translate the tap
                // to be relative to the center of the widget.
                final centerOfWidget = size.toOffset / 2.0;
                final tapFromCenter = tapInWidget - centerOfWidget;

                // The field is in a SizedBox of finalSize, so the tap
                // might be outside the field.
                if (!Rect.fromCenter(
                  center: Offset.zero,
                  width: finalSize.width,
                  height: finalSize.height,
                ).contains(tapFromCenter)) {
                  return;
                }

                // Now, go from the coordinate space of the centered field back
                // to the un-rotated, un-scaled field space.
                final angle = -radians(model.fieldRotation);
                final xUnrotated =
                    tapFromCenter.dx * cos(angle) -
                    tapFromCenter.dy * sin(angle);
                final yUnrotated =
                    tapFromCenter.dx * sin(angle) +
                    tapFromCenter.dy * cos(angle);

                // Un-scale from display pixels to image pixels
                final xImage = xUnrotated / scale;
                final yImage = yUnrotated / scale;

                // Go from image pixels relative to center to image pixels relative to TL
                final xImageFromTL = xImage + model.field.center.dx;
                final yImageFromTL = -yImage + model.field.center.dy;

                // Go from image pixels to meters
                final xMeters =
                    xImageFromTL / model.field.pixelsPerMeterHorizontal;
                final yMeters =
                    yImageFromTL / model.field.pixelsPerMeterVertical;

                model.commanderTopics.set(Offset(xMeters, yMeters));
              }
            },
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: finalSize.width,
                    height: finalSize.height,
                    child: ClipRect(
                      child: UnconstrainedBox(
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: (model.fieldRotation / 90.0).round(),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform(
                                  transform:
                                      Matrix4.identity(), //!model.allianceTopic.value
                                  // ? Matrix4.diagonal3Values(-1, -1, 1)
                                  // : Matrix4.identity(),
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: imageDisplaySize.width,
                                    height: imageDisplaySize.height,
                                    child: child!,
                                  ),
                                ),
                                CustomPaint(
                                  size: imageDisplaySize,
                                  painter: RobotPainter(
                                    center: imageDisplaySize.toOffset / 2,
                                    field: model.field,
                                    robotPose: Offset(robotX, robotY),
                                    robotAngle: robotTheta,
                                    robotSize: Size(
                                      model.robotWidthMeters,
                                      model.robotLengthMeters,
                                    ),
                                    robotColor: model.robotColor,
                                    robotImage: model.robotImage,
                                    scale: scale,
                                  ),
                                ),
                                CustomPaint(
                                  //Hub Activation
                                  size: imageDisplaySize,
                                  painter: HubPainter(
                                    center: imageDisplaySize.toOffset / 2,
                                    pos: (model.allianceTopic.value)
                                        ? Offset(4.62, 4.04)
                                        : Offset(11.89, 4.04),
                                    field: model.field,
                                    enemy: false,
                                    color: (bothHubEnabled || hubEnabled)
                                        ? ((shiftTimerNumber() > 8 ||
                                                  flashHub() ||
                                                  wontBeDisabled(false))
                                              ? (model.allianceTopic.value
                                                    ? Color.fromARGB(
                                                        255,
                                                        0,
                                                        0,
                                                        255,
                                                      )
                                                    : Color.fromARGB(
                                                        255,
                                                        255,
                                                        0,
                                                        0,
                                                      ))
                                              : Color.fromARGB(255, 0, 0, 0))
                                        : Color.fromARGB(255, 0, 0, 0),
                                    scale: scale,
                                  ),
                                ),
                                CustomPaint(
                                  //Enemy Hub Activation
                                  size: imageDisplaySize,
                                  painter: HubPainter(
                                    center: imageDisplaySize.toOffset / 2,
                                    pos: (!model.allianceTopic.value)
                                        ? Offset(4.62, 4.04)
                                        : Offset(11.89, 4.04),
                                    field: model.field,
                                    enemy: true,
                                    color: (bothHubEnabled || !hubEnabled)
                                        ? ((shiftTimerNumber() > 8 ||
                                                  flashHub() ||
                                                  wontBeDisabled(true))
                                              ? (!model.allianceTopic.value
                                                    ? Color.fromARGB(
                                                        255,
                                                        0,
                                                        0,
                                                        255,
                                                      )
                                                    : Color.fromARGB(
                                                        255,
                                                        255,
                                                        0,
                                                        0,
                                                      ))
                                              : Color.fromARGB(255, 0, 0, 0))
                                        : (Color.fromARGB(255, 0, 0, 0)),
                                    scale: scale,
                                  ),
                                ),
                                CustomPaint(
                                  //aliance square paint
                                  size: imageDisplaySize,
                                  painter: AlliancePainter(
                                    center: imageDisplaySize.toOffset / 2,
                                    field: model.field,
                                    color: model.allianceTopic.value
                                        ? Color.fromARGB(255, 0, 0, 255)
                                        : Color.fromARGB(255, 255, 0, 0),
                                    width: imageDisplaySize.width,
                                    height: imageDisplaySize.height,
                                    status: emergencyStopped
                                        ? 2
                                        : _flagMatches(
                                            controlData,
                                            ENABLED_FLAG,
                                          )
                                        ? 0
                                        : 1,
                                  ),
                                ),
                                if (model.showTrajectories)
                                  for (List<Offset> points in trajectoryPoints)
                                    CustomPaint(
                                      size: imageDisplaySize,
                                      painter: TrajectoryPainter(
                                        center: imageDisplaySize.toOffset / 2,
                                        color: model.trajectoryColor,
                                        points: points,
                                        strokeWidth:
                                            model.trajectoryPointSize *
                                            model
                                                .field
                                                .pixelsPerMeterHorizontal *
                                            scale,
                                      ),
                                    ),
                                if (model.showGamePieces)
                                  CustomPaint(
                                    size: imageDisplaySize,
                                    painter: GamePiecePainter(
                                      center: imageDisplaySize.toOffset / 2,
                                      field: model.field,
                                      gamePieces: model.gamePieceTopics.value,
                                      gamePieceColor: model.gamePieceColor,
                                      bestGamePieceColor:
                                          model.bestGamePieceColor,
                                      markerSize: model.gamePieceMarkerSize,
                                      scale: scale,
                                    ),
                                  ),
                                if (model.showVisionTargets)
                                  CustomPaint(
                                    size: imageDisplaySize,
                                    painter: VisionPainter(
                                      center: imageDisplaySize.toOffset / 2,
                                      field: model.field,
                                      poses: [
                                        for (
                                          int i = 0;
                                          i <
                                              model
                                                      .visionTopics
                                                      .allTags
                                                      .value
                                                      .length /
                                                  7;
                                          i++
                                        )
                                          //model.visionTopics.allTags.value[i*7+1] = X (Horizontal Offset From Principal Pixel To Target (degrees))
                                          //model.visionTopics.allTags.value[i*7+2] = Y (Vertical Offset From Principal Pixel To Target (degrees))
                                          //model.visionTopics.allTags.value[i*7+3] = ta (Target Area (0% of image to 100% of image))
                                          //model.visionTopics.allTags.value[i*7+4] = distToCamera
                                          //model.visionTopics.allTags.value[i*7+5] = distToRobot
                                          //model.visionTopics.allTags.value[i*7+6] = ambiguity (?)
                                          // the message no longer contains metres – the two offsets are
                                          // horizontal/vertical angles (degrees) from the principal pixel.
                                          // convert them into a world‑frame point using the camera
                                          // intrinsics (1280×800 in your case) and the camera’s
                                          // extrinsics (XYZ + yaw/pitch/roll) before finally rotating/adding
                                          // the robot pose.
                                          () {
                                            // raw values from the packet
                                            // final double horizPix = model.visionTopics.allTags.value[i * 7 + 2] as double;
                                            // final double vertPix   = model.visionTopics.allTags.value[i * 7 + 1] as double;
                                            // final double distCam  = model.visionTopics.allTags.value[i * 7 + 4] as double;

                                            // // camera intrinsics
                                            // // resolution constants – useful if you ever want to convert
                                            // // pixel offsets instead of angle offsets
                                            // const double camResX = 1280.0;
                                            // const double camResY = 800.0;
                                            // const double focalLength = 1600.0; // adjust based on your camera calibration (i don't fucking know)

                                            // // convert pixel offsets to angles
                                            // final double hRad = atan((horizPix - camResX / 2) / focalLength);
                                            // final double vRad = atan((vertPix - camResY / 2) / focalLength);

                                            // // build a direction vector in the camera coordinate system.
                                            // // +z forward, +x right, +y down; magnitude = reported distance.

                                            //values are in degrees (txnc & tync)
                                            final double horizDeg =
                                                -model
                                                        .visionTopics
                                                        .allTags
                                                        .value[i * 7 + 2]
                                                    as double;
                                            final double vertDeg =
                                                model
                                                        .visionTopics
                                                        .allTags
                                                        .value[i * 7 + 1]
                                                    as double;
                                            final double distCam =
                                                model
                                                        .visionTopics
                                                        .allTags
                                                        .value[i * 7 + 4]
                                                    as double;

                                            // convert offsets to radians
                                            final double hRad = radians(
                                              horizDeg,
                                            );
                                            final double vRad = radians(
                                              vertDeg,
                                            );

                                            // build a direction vector in the camera coordinate system.
                                            // +z forward, +x right, +y down; magnitude = reported distance.
                                            // Vector3 camVec = Vector3(
                                            //   distCam * tan(hRad), // x
                                            //   distCam * tan(vRad), // y
                                            //   distCam,             // z
                                            // );

                                            Vector3 camVec = Vector3(
                                              distCam * tan(hRad), // x
                                              distCam * tan(vRad), // y
                                              distCam, // z
                                            );

                                            // apply the camera’s extrinsic transform (translation + yaw/pitch/roll)
                                            final double camYaw = radians(
                                              model
                                                      .visionTopics
                                                      .cameraData
                                                      .value[3] ??
                                                  0.0,
                                            );
                                            final double camPitch = radians(
                                              model
                                                      .visionTopics
                                                      .cameraData
                                                      .value[4] ??
                                                  0.0,
                                            );
                                            final double camRoll = radians(
                                              model
                                                      .visionTopics
                                                      .cameraData
                                                      .value[5] ??
                                                  0.0,
                                            );
                                            Matrix4 camTransform =
                                                Matrix4.identity()
                                                  ..translateByVector3(
                                                    Vector3(
                                                      model
                                                              .visionTopics
                                                              .cameraData
                                                              .value[0] ??
                                                          0.0,
                                                      -model
                                                              .visionTopics
                                                              .cameraData
                                                              .value[1] ??
                                                          0.0,
                                                      model
                                                              .visionTopics
                                                              .cameraData
                                                              .value[2] ??
                                                          0.0,
                                                    ),
                                                  )
                                                  ..rotateZ(camYaw)
                                                  ..rotateX(camPitch)
                                                  ..rotateY(camRoll);
                                            Vector3 worldCam = camTransform
                                                .transform3(camVec);

                                            // worldCam.x += (worldCam.x*distCam);
                                            // worldCam.y += (worldCam.y*distCam);

                                            // worldCam.x += worldCam.x * distCam * cos(robotTheta-pi/2);
                                            // worldCam.y += worldCam.y * distCam * sin(robotTheta-pi/2);

                                            // rotate/translate into field coordinates using robot pose
                                            double cosR = cos(
                                              redAlliance
                                                  ? robotTheta + pi
                                                  : robotTheta,
                                            );
                                            double sinR = sin(
                                              redAlliance
                                                  ? robotTheta + pi
                                                  : robotTheta,
                                            );
                                            worldCam.x *= (cosR * distCam);
                                            worldCam.y *= (sinR * distCam);
                                            // worldCam.x *= distCam;
                                            // worldCam.y *= distCam;

                                            double xField =
                                                robotX +
                                                (cosR * worldCam.x -
                                                    sinR *
                                                        worldCam.y); //*distCam;
                                            double yField =
                                                robotY +
                                                (sinR * worldCam.x +
                                                    cosR *
                                                        worldCam.y); //*distCam;

                                            //logger.debug('Cam: ${model.visionTopics.cameraData.value} = ${Offset(xField, yField)} vrs ${Offset(robotX+((cos(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+1] as double)) - (sin(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+2] as double))), robotY+((sin(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+1] as double)) + (cos(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+2] as double))))}');
                                            return Offset(xField, yField);
                                          }(),
                                        // robotX+((cos(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+1] as double)) - (sin(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+2] as double))),
                                        // robotY+((sin(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+1] as double)) + (cos(robotTheta-pi/2) * (model.visionTopics.allTags.value[i*7+2] as double))),
                                      ],
                                      statuses: [
                                        [
                                          for (
                                            int i = 0;
                                            i <
                                                model
                                                        .visionTopics
                                                        .allTags
                                                        .value
                                                        .length /
                                                    7;
                                            i++
                                          )
                                            model.visionTopics.allTags.value[i *
                                                7],
                                        ],
                                        [
                                          for (
                                            int i = 0;
                                            i <
                                                model
                                                        .visionTopics
                                                        .allTags
                                                        .value
                                                        .length /
                                                    7;
                                            i++
                                          )
                                            model.visionTopics.allTags.value[i *
                                                    7 +
                                                4],
                                        ],
                                      ],

                                      color: model.visionTargetColor,
                                      markerSize: model.visionMarkerSize,
                                      scale: scale,
                                    ),
                                  ),
                                if (model.showOtherObjects)
                                  CustomPaint(
                                    size: imageDisplaySize,
                                    painter: OtherObjectsPainter(
                                      center: imageDisplaySize.toOffset / 2,
                                      field: model.field,
                                      subscriptions:
                                          model.otherObjectSubscriptions,
                                      isPoseStruct: model.isPoseStruct,
                                      isPoseArrayStruct:
                                          model.isPoseArrayStruct,
                                      robotColor:
                                          model.gamePieceColor, //robotColor,
                                      objectSize: model.otherObjectSize,
                                      scale: scale,
                                    ),
                                  ),
                                if (model.showSpecialMarkers)
                                  CustomPaint(
                                    size: imageDisplaySize,
                                    painter: SpecialMarkerPainter(
                                      center: imageDisplaySize.toOffset / 2,
                                      field: model.field,
                                      markers:
                                          model.specialMarkerTopics.markers,
                                      scale: scale,
                                    ),
                                  ),
                                SizedBox(
                                  width: imageDisplaySize.width * 0.95,
                                  height: imageDisplaySize.height * 0.95,
                                  child: Center(
                                    child: Column(
                                      children: [
                                        const Spacer(flex: 1),
                                        //matchDisplayWidget,
                                        Row(
                                          children: [
                                            fmsDisplayIcon,
                                            const SizedBox(width: 5),
                                            Text(fmsDisplayString),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            dsDisplayIcon,
                                            const SizedBox(width: 5),
                                            Text(dsDisplayString),
                                          ],
                                        ),
                                        const Spacer(),
                                        // Robot State
                                        robotStateWidget,
                                      ],
                                    ),
                                  ),
                                ),
                                // ),
                                // ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: imageDisplaySize.width * 0.95,
                  height: imageDisplaySize.height * 0.95,
                  child: Center(
                    child: Column(
                      children: [
                        //const Spacer(flex: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            matchDisplayWidget,
                            Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 2.0,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(
                                  alpha: 0.5 * 255,
                                ),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              //child: matchDisplayWidget,
                              child: Text(
                                'X: ${formatDouble(robotX, 2, 2)}, Y: ${formatDouble(robotY, 2, 2)}, Heading: ${formatDouble(degrees(robotTheta), 2, 3)}°',
                                style:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                              ),
                            ),
                            //if (gameMessage(false) != '')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 2.0,
                              ),
                              decoration: BoxDecoration(
                                color: gameMessage(true).contains('R')
                                    ? const Color.fromARGB(
                                        255,
                                        255,
                                        0,
                                        0,
                                      ).withValues(alpha: 0.5 * 255)
                                    : gameMessage(true).contains('B')
                                    ? const Color.fromARGB(
                                        255,
                                        0,
                                        0,
                                        255,
                                      ).withValues(alpha: 0.5 * 255)
                                    : const Color.fromARGB(
                                        255,
                                        255,
                                        125,
                                        0,
                                      ).withValues(alpha: 0.5 * 255),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Text(
                                gameMessage(false),
                                style:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (pose.dx > 0.0)
                  Positioned(
                    //for right sided:
                    // bottom: 10,
                    // left: size.width-40,
                    top: size.height - 30,
                    left: 0,
                    right: 0,
                    child: Center(
                      //for right sided:
                      // child: RotatedBox(
                      // quarterTurns: 3, // rotate -90°
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 122, 79, 14),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'X: ${pose.dx.toStringAsFixed(2)}, Y: ${pose.dy.toStringAsFixed(2)}',
                          style:
                              Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                        ),
                      ),
                      // ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// class TrianglePainter extends CustomPainter {
//   final Color strokeColor;
//   final PaintingStyle paintingStyle;
//   final double strokeWidth;

//   TrianglePainter({
//     this.strokeColor = Colors.white,
//     this.strokeWidth = 3,
//     this.paintingStyle = PaintingStyle.stroke,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     Paint paint = Paint()
//       ..color = strokeColor
//       ..strokeWidth = strokeWidth
//       ..style = paintingStyle;

//     canvas.drawPath(getTrianglePath(size.width, size.height), paint);
//   }

//   Path getTrianglePath(double x, double y) => Path()
//     ..moveTo(0, 0)
//     ..lineTo(x, y / 2)
//     ..lineTo(0, y)
//     ..lineTo(0, 0)
//     ..lineTo(x, y / 2);

//   @override
//   bool shouldRepaint(TrianglePainter oldDelegate) =>
//       oldDelegate.strokeColor != strokeColor ||
//       oldDelegate.paintingStyle != paintingStyle ||
//       oldDelegate.strokeWidth != strokeWidth;
// }

// class TrajectoryPainter extends CustomPainter {
//   final Offset center;
//   final List<Offset> points;
//   final double strokeWidth;
//   final Color color;

//   TrajectoryPainter({
//     required this.center,
//     required this.points,
//     required this.strokeWidth,
//     this.color = Colors.white,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (points.isEmpty) {
//       return;
//     }
//     Paint trajectoryPaint = Paint()
//       ..color = color
//       ..strokeWidth = strokeWidth
//       ..style = PaintingStyle.stroke
//       ..strokeCap = StrokeCap.round;
//     Path trajectoryPath = Path();

//     trajectoryPath.moveTo(points[0].dx + center.dx, points[0].dy + center.dy);

//     for (Offset point in points) {
//       trajectoryPath.lineTo(point.dx + center.dx, point.dy + center.dy);
//     }
//     canvas.drawPath(trajectoryPath, trajectoryPaint);
//   }

//   @override
//   bool shouldRepaint(TrajectoryPainter oldDelegate) =>
//       oldDelegate.points != points ||
//       oldDelegate.strokeWidth != strokeWidth ||
//       oldDelegate.color != color;
// }

class _BlackAndYellowStripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);

    const DiagonalStripesThick(
      bgColor: Colors.black,
      fgColor: Colors.yellow,
      featuresCount: 10,
    ).paintOnRect(canvas, size, rect);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
