import 'package:elastic_dashboard/widgets/nt_widgets/multi_topic/field_widget/field_widget.dart'
    as field_widget;

import 'package:flutter/material.dart';

import 'package:elastic_dashboard/services/nt4_client.dart';
import 'package:elastic_dashboard/services/nt4_type.dart';
import 'package:elastic_dashboard/services/nt_connection.dart';

class SubscribedTopic<T extends Object?> {
  final NTConnection ntConnection;
  final String topic;
  final T defaultValue;
  final double period;

  late NT4Subscription subscription;

  SubscribedTopic({
    required this.ntConnection,
    required this.topic,
    required this.defaultValue,
    this.period = 0.1,
  });

  void subscribe() {
    subscription = ntConnection.subscribe(topic, period);
  }

  void unsubscribe() {
    ntConnection.unSubscribe(subscription);
  }

  T get value {
    final subValue = subscription.value;
    if (subValue is T) {
      return subValue;
    }
    return defaultValue;
  }
}

class FMSTopics {
  final NTConnection ntConnection;
  final double period;
  late final SubscribedTopic<List<dynamic>> data;

  late final List<SubscribedTopic> topics;

  FMSTopics({required this.ntConnection, this.period = 0.1}) {
    data = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/FMSInfo',
      defaultValue: const [
        '',
        0,
        '',
        true,
        null,
      ], //EventName,FMSControlData,GameSpecificMessage,IsRedAlliance,MatchNumber,MatchType,ReplayNumber,StationNumber
    );

    topics = [data];
  }
}

// Manages all vision-related NT topics.
class VisionTopics {
  final NTConnection ntConnection;
  final double period;

  // late final SubscribedTopic<double> closeCamX;
  // late final SubscribedTopic<double> closeCamY;
  // late final SubscribedTopic<double> farCamX;
  // late final SubscribedTopic<double> farCamY;
  // late final SubscribedTopic<double> leftCamX;
  // late final SubscribedTopic<double> leftCamY;
  // late final SubscribedTopic<double> rightCamX;
  // late final SubscribedTopic<double> rightCamY;

  // late final SubscribedTopic<bool> rightCamLocation;
  // late final SubscribedTopic<bool> rightCamHeading;
  // late final SubscribedTopic<bool> leftCamLocation;
  // late final SubscribedTopic<bool> leftCamHeading;
  // late final SubscribedTopic<bool> closeCamLocation;
  // late final SubscribedTopic<bool> closeCamHeading;
  // late final SubscribedTopic<bool> farCamLocation;
  // late final SubscribedTopic<bool> farCamHeading;

  //late final SubscribedTopic<List<double>> _target_pose;
  late final SubscribedTopic<List<dynamic>> mainTag; //THIS! THIS WORKS
  late final SubscribedTopic<List<dynamic>> allTags; //THIS! THIS WORKS
  late final SubscribedTopic<dynamic> allTagsjson; //THIS! THIS WORKS
  late final SubscribedTopic<List<dynamic>> cameraData;

  NT4Subscription get subscription => mainTag.subscription;

  late final List<SubscribedTopic> topics;

  VisionTopics({required this.ntConnection, this.period = 0.1}) {
    // closeCamX = SubscribedTopic(
    //   ntConnection: ntConnection,
    //   topic: '/Match/Pose/CloseCamX',
    //   defaultValue: 0.0,
    // );
    // rightCamLocation = SubscribedTopic(
    //   ntConnection: ntConnection,
    //   topic: '/Match/Streams/RightLime/Location',
    //   defaultValue: false,
    // );
    mainTag = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/limelight-one/targetpose_robotspace',
      defaultValue: const [8.0, 4.0, 0.0, 0.0, 0.0, 0.0, 6],
    );
    allTags = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/limelight-one/rawfiducials',
      defaultValue: const [
        0,
        0.0,
        0.0,
        1.0,
        1.0,
        1.0,
        0,
      ], //[id, txnc, tync, ta, distToCamera, distToRobot, ambiguity, id2.....]
    );
    allTagsjson = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/limelight-one/json',
      defaultValue: const [''], 
    );

    cameraData = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/limelight-one/camerapose_robotspace',
      defaultValue: const [
        0.0,
        0.0,
        0.0,
        1.0,
        1.0,
        1.0,
        6,
      ], //array of data of the camera pos.
    );

    topics = [
      mainTag,
      allTags,
      allTagsjson,
      cameraData,
    ];
  }

  void initialize() {
    for (var topic in topics) {
      topic.subscribe();
    }
  }

  void dispose() {
    for (var topic in topics) {
      topic.unsubscribe();
    }
  }

  List<Listenable> get listenables =>
      topics.map((topic) => topic.subscription).toList();

  // Offset get closeCamPose => Offset(closeCamX.value, closeCamY.value);
  // Offset get farCamPose => Offset(farCamX.value, farCamY.value);
  // Offset get leftCamPose => Offset(leftCamX.value, leftCamY.value);
  // Offset get rightCamPose => Offset(rightCamX.value, rightCamY.value);

  Offset get targetPose => Offset(
    mainTag.value.isEmpty ? 8.0 : (mainTag.value[0] ?? 8.0),
    mainTag.value.isEmpty ? 8.0 : (mainTag.value[2] ?? 4.0),
  );
}

// Manages all game-piece-related NT topics.
class GamePieceTopics {
  final NTConnection ntConnection;
  final double period;

  late final SubscribedTopic<List<dynamic>> gamePieces;

  GamePieceTopics({required this.ntConnection, this.period = 0.1}) {
    gamePieces = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/SmartDashboard/Field/Pieces',
      defaultValue: const <double>[],
    );
  }

  void initialize() => gamePieces.subscribe();
  void dispose() => gamePieces.unsubscribe();

  List<Listenable> get listenables => [gamePieces.subscription];

  List<Offset> get value {
    List<dynamic> raw = gamePieces.value;

    List<Offset> offsets = [];
    // The list is [x1, y1, x2, y2, ...], so we iterate by 2.
    for (int i = 0; i < raw.length; i += 2) {
      // Make sure there is a pair of coordinates
      if (i + 1 < raw.length) {
        offsets.add(Offset(raw[i], raw[i + 1]));
      }
    }
    return offsets;
  }
}

// Manages the FMS alliance color topic.
class AllianceTopic {
  final NTConnection ntConnection;
  final double period;

  late final SubscribedTopic<bool> isRedAlliance;

  AllianceTopic({required this.ntConnection, this.period = 0.1}) {
    isRedAlliance = SubscribedTopic(
      ntConnection: ntConnection,
      topic: '/FMSInfo/IsRedAlliance',
      defaultValue: false,
    );
  }

  void initialize() => isRedAlliance.subscribe();
  void dispose() => isRedAlliance.unsubscribe();

  List<Listenable> get listenables => [isRedAlliance.subscription];

  bool get value => !isRedAlliance.value;
}

// Manages topics for commanding the robot pose.
class CommanderTopics {
  final NTConnection ntConnection;

  // late final NT4Topic robotX;
  // late final NT4Topic robotY;
  late final NT4Topic robotXY;
  // late final NT4Topic setNewPose;

  CommanderTopics({required this.ntConnection}) {
    // robotX = ntConnection.publishNewTopic(
    //   '/Match/Commander/RobotPosResetX',
    //   // '/SmartDashboard/Field/TouchPos/X',
    //   NT4Type.double(),
    // );
    // robotY = ntConnection.publishNewTopic(
    //   '/Match/Commander/RobotPosResetY',
    //   NT4Type.double(),
    // );
    robotXY = ntConnection.publishNewTopic(
      '/SmartDashboard/Field/TouchPos',
      NT4Type.array(NT4Type.double()),
    );
    // setNewPose = ntConnection.publishNewTopic(
    //   '/Match/Commander/NewPosData',
    //   NT4Type.boolean(),
    // );
  }

  void unpublish() {
    // ntConnection.unpublishTopic(robotX);
    ntConnection.unpublishTopic(robotXY);
    // ntConnection.unpublishTopic(robotY);
    // ntConnection.unpublishTopic(setNewPose);
  }

  void set(Offset pose) {
    // ntConnection.updateDataFromTopic(robotX, pose.dx);
    // ntConnection.updateDataFromTopic(robotY, pose.dy);
    ntConnection.updateDataFromTopic(robotXY, [pose.dx, pose.dy, 0.0]);
    field_widget.pose = pose;
    // ntConnection.updateDataFromTopic(setNewPose, true);
  }
}
