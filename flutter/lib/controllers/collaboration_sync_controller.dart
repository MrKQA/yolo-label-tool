import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/annotation.dart';
import '../models/collaboration.dart';
import '../services/annotation_database_codec.dart';
import '../services/app_runtime.dart';
import '../services/collaboration_codec.dart';
import '../services/config_store.dart';
import '../services/logger.dart';
import 'collaboration_controller.dart';
import 'project_controller.dart';

/// Coordinates collaboration snapshots between transport and project state.
class CollaborationSyncController {
  CollaborationSyncController({
    required this.collaboration,
    required this.project,
    Directory? cacheDirectory,
  }) : cacheDirectory =
           cacheDirectory ??
           Directory(
             '${ConfigStore.projectDirectory.path}\\collaboration_cache',
           );

  final CollaborationController collaboration;
  final ProjectController project;
  final Directory cacheDirectory;

  Map<String, Object?> projectSnapshotMessage({
    int? assignmentStart,
    int? assignmentEnd,
  }) {
    return collaborationProjectSnapshotToJson(
      projectKey: annotationDatabaseProjectKey(
        importedDataset: project.importedDataset,
        images: project.images,
      ),
      images: project.images,
      imageSplits: project.imageSplits,
      imageDisplaySizes: project.imageDisplaySizes,
      classes: project.labelClasses,
      annotationsByImage: project.annotationsByImage,
      assignmentStart: assignmentStart ?? collaboration.assignmentStart,
      assignmentEnd: assignmentEnd ?? collaboration.assignmentEnd,
      fallbackAuthorId: collaboration.authorId,
      fallbackAuthorName: collaboration.annotatorName,
      fallbackAuthorColorValue: collaboration.annotatorColorValue,
      imageBytesBase64: _imageBytesBase64,
    );
  }

  List<Map<String, Object?>> classesPayload() {
    return collaborationClassesToJson(project.labelClasses);
  }

  Map<String, Object?> annotationPayload(AnnotationRegion annotation) {
    return collaborationAnnotationToJson(
      annotation,
      fallbackAuthorId: collaboration.authorId,
      fallbackAuthorName: collaboration.annotatorName,
      fallbackAuthorColorValue: collaboration.annotatorColorValue,
    );
  }

  bool publishCurrentAnnotations() {
    if (collaboration.mode == CollaborationMode.off ||
        project.images.isEmpty ||
        !collaboration.isImageIndexAuthorized(
          project.selectedImageIndex,
          project.images.length,
        )) {
      return false;
    }
    final image = project.selectedImage;
    if (image == null) {
      return false;
    }
    final permissions = collaboration.selfPermissions;
    final limitedToOwnAnnotations =
        collaboration.mode == CollaborationMode.client &&
        !permissions.canEditOthers &&
        !permissions.canDeleteOthers &&
        !permissions.canChangeClass;
    final current = project.currentAnnotations;
    final annotations = limitedToOwnAnnotations
        ? current
              .where(
                (annotation) =>
                    annotation.authorId.isEmpty ||
                    annotation.authorId == collaboration.authorId,
              )
              .toList(growable: false)
        : current;
    final message = <String, Object?>{
      'type': 'annotation_snapshot',
      'imagePath': image.path,
      'imageIndex': project.selectedImageIndex + 1,
      'sourceUserId': collaboration.authorId,
      'authoritative': !limitedToOwnAnnotations,
      if (limitedToOwnAnnotations) 'authorScope': collaboration.authorId,
      if (collaboration.mode == CollaborationMode.host)
        'classes': classesPayload(),
      'annotations': [
        for (final annotation in annotations) annotationPayload(annotation),
      ],
    };
    if (collaboration.mode == CollaborationMode.host) {
      collaboration.sendMessageToAuthorizedPeers(
        message,
        project.selectedImageIndex,
      );
    } else {
      unawaited(collaboration.sendHostMessage(message));
    }
    return true;
  }

  bool applyProjectSnapshot(Map<String, dynamic> message) {
    final snapshot = collaborationProjectSnapshotFromJson(
      message,
      resolveLocalImage: _resolveLocalImage,
      fallbackAssignmentStart: collaboration.assignmentStart,
      fallbackAssignmentEnd: collaboration.assignmentEnd,
      currentAnnotationSerial: project.annotationSerial,
    );
    if (snapshot == null) {
      return false;
    }
    collaboration.assignmentStart = snapshot.assignmentStart;
    collaboration.assignmentEnd = snapshot.assignmentEnd;
    final firstAuthorizedIndex = (snapshot.assignmentStart - 1)
        .clamp(0, snapshot.images.length - 1)
        .toInt();
    project.applyProjectSnapshot(
      images: snapshot.images,
      splits: snapshot.splits,
      displaySizes: snapshot.displaySizes,
      classes: snapshot.classes,
      annotations: snapshot.annotations,
      selectedIndex: firstAuthorizedIndex,
      nextClassSerial: snapshot.nextClassSerial,
      nextAnnotationSerial: snapshot.nextAnnotationSerial,
    );
    return true;
  }

  bool applyClassSnapshot(Map<String, dynamic> message) {
    if (message['classes'] is! List) {
      return false;
    }
    project.replaceLabelClasses(
      collaborationClassesFromJson(message['classes']),
    );
    return true;
  }

  bool applyAnnotationSnapshot(
    Map<String, dynamic> message, {
    required String fromUserId,
  }) {
    if (collaboration.mode == CollaborationMode.off) {
      return false;
    }
    final imageIndex = collaborationInt(message, 'imageIndex', fallback: 0) - 1;
    if (imageIndex < 0 || imageIndex >= project.images.length) {
      return false;
    }
    if (collaboration.mode == CollaborationMode.host && fromUserId.isNotEmpty) {
      CollaborationPeer? sourcePeer;
      for (final peer in collaboration.peers) {
        if (peer.userId == fromUserId) {
          sourcePeer = peer;
          break;
        }
      }
      if (sourcePeer == null ||
          !sourcePeer.online ||
          !collaboration.peerCanAccessImage(sourcePeer, imageIndex)) {
        return false;
      }
    }
    if (collaboration.mode == CollaborationMode.client &&
        !collaboration.isImageIndexAuthorized(
          imageIndex,
          project.images.length,
        )) {
      return false;
    }
    final snapshot = collaborationAnnotationSnapshotFromJson(
      message,
      fromUserId: fromUserId,
      selfUserId: collaboration.authorId,
      selfUserName: collaboration.annotatorName,
      selfUserColorValue: collaboration.annotatorColorValue,
      peers: collaboration.peers,
    );
    if (snapshot == null) {
      return false;
    }
    if (snapshot.hasClassPayload) {
      project.replaceLabelClasses(snapshot.classes);
    }
    project.applyAnnotationSnapshot(
      imagePath: project.images[imageIndex].path,
      incoming: snapshot.annotations,
      authoritative: snapshot.authoritative,
      scopedAuthors: snapshot.scopedAuthors,
    );
    if (collaboration.mode == CollaborationMode.host) {
      collaboration.sendMessageToAuthorizedPeers(
        {...message, 'sourceUserId': fromUserId, 'classes': classesPayload()},
        imageIndex,
        excludeUserId: fromUserId,
      );
    }
    return true;
  }

  void broadcastClassSnapshot(String reason) {
    if (collaboration.mode != CollaborationMode.host) {
      return;
    }
    unawaited(
      collaboration.broadcastMessage(
        collaborationClassSnapshotToJson(project.labelClasses),
      ),
    );
    logApp(
      'COLLAB',
      'Class snapshot broadcast: reason=$reason, classes=${project.labelClasses.length}',
      level: AppLogLevel.debug,
    );
  }

  void broadcastProjectSnapshot(String reason) {
    if (collaboration.mode != CollaborationMode.host) {
      return;
    }
    final count = collaboration.sendMessageToOnlinePeers(
      (peer) => projectSnapshotMessage(
        assignmentStart: peer.assignmentStart,
        assignmentEnd: peer.assignmentEnd,
      ),
    );
    logApp(
      'COLLAB',
      'Project snapshot broadcast: reason=$reason, peers=$count, images=${project.images.length}',
      level: AppLogLevel.debug,
    );
  }

  void broadcastAllAnnotations(String reason) {
    if (collaboration.mode != CollaborationMode.host ||
        project.images.isEmpty) {
      return;
    }
    for (var index = 0; index < project.images.length; index++) {
      final image = project.images[index];
      collaboration.sendMessageToAuthorizedPeers({
        'type': 'annotation_snapshot',
        'imagePath': image.path,
        'imageIndex': index + 1,
        'sourceUserId': collaboration.authorId,
        'authoritative': true,
        'classes': classesPayload(),
        'annotations': [
          for (final annotation in project.annotationsForPath(image.path))
            annotationPayload(annotation),
        ],
      }, index);
    }
    logApp(
      'COLLAB',
      'Annotation snapshots broadcast: reason=$reason, images=${project.images.length}',
      level: AppLogLevel.debug,
    );
  }

  String _imageBytesBase64(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return '';
      }
      return base64Encode(file.readAsBytesSync());
    } on Object catch (error) {
      logApp(
        'COLLAB',
        'Image payload read failed: path=$path, error=$error',
        level: AppLogLevel.warning,
      );
      return '';
    }
  }

  String _resolveLocalImage(
    String remotePath,
    String name,
    String bytesBase64,
  ) {
    if (File(remotePath).existsSync() || bytesBase64.trim().isEmpty) {
      return remotePath;
    }
    try {
      final bytes = base64Decode(bytesBase64);
      if (!cacheDirectory.existsSync()) {
        cacheDirectory.createSync(recursive: true);
      }
      final cacheName = collaborationCacheFileName(remotePath, name);
      final file = File('${cacheDirectory.path}\\$cacheName');
      file.writeAsBytesSync(bytes);
      return file.path;
    } on Object catch (error) {
      logApp(
        'COLLAB',
        'Image payload write failed: path=$remotePath, error=$error',
        level: AppLogLevel.warning,
      );
      return remotePath;
    }
  }
}
