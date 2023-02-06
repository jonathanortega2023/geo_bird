import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import './services/geo.dart';

List<CameraDescription> _cameras = <CameraDescription>[];
Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    _cameras = await availableCameras();
    runApp(MaterialApp(home: PhotoPage()));
  } on CameraException catch (e) {
    _logError(e.code, e.description);
    runApp(MaterialApp(home: CameraErrorPage(cameraException: e)));
  }
}

class CameraErrorPage extends StatelessWidget {
  final CameraException cameraException;
  const CameraErrorPage({required this.cameraException, super.key});
  @override
  Widget build(BuildContext context) {
    if (cameraException.description == null) {
      return Scaffold(
        body: Center(child: Text(cameraException.code)),
      );
    } else {
      return Scaffold(
        body: Center(
            child: Text(
                "${cameraException.code}: ${cameraException.description}")),
      );
    }
  }
}

void _logError(String code, String? message) {
  // ignore: avoid_print
  print('Error: $code${message == null ? '' : '\nError Message: $message'}');
}

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  late PageController pageController = PageController();
  CameraController? controller =
      CameraController(_cameras.first, ResolutionPreset.max);
  XFile? imageFile;
  Position? geoPosition;
  late String birdSpecies;

  List<String> speciesList = ["Birb", "Cardinal", "Penguin"];
  @override
  void initState() {
    try {
      determinePosition().then((Position? position) {
        setState(() {
          geoPosition = position;
        });
        print('''
                Lat: ${geoPosition.toString()}
                Accuracy: ${geoPosition!.accuracy}
                GeoTimestamp: ${geoPosition!.timestamp}
                ''');
      });
    } on GeolocatorException catch (e) {
      _logError(e.code, e.message);
      showInSnackBar(e.message);
    } on Exception catch (e) {
      print(e.toString());
      showInSnackBar(e.toString());
    }

    try {
      controller?.initialize();
    } on CameraException catch (e) {
      _handleFailedCameraInit(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
          body: imageFile == null ? takePhotoScreen() : submitPhotoPages()),
    );
  }

  PageView submitPhotoPages() {
    Column verifyPhoto() {
      return Column(
        children: [
          Image.file(File(imageFile!.path)),
          ButtonBar(
            alignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                  onPressed: () {
                    setState(() {
                      imageFile = null;
                      geoPosition = null;
                      controller = CameraController(
                          _cameras.first, ResolutionPreset.max);
                    });
                  },
                  child: const Text("Retake")),
              TextButton(
                  onPressed: () {
                    pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInCubic);
                  },
                  child: const Text("Add species")),
            ],
          )
        ],
      );
    }

    Column addSpecies() {
      return Column(
        children: [
          TypeAheadField(
            animationStart: 1,
            itemBuilder: (context, suggestion) {
              return ListTile(
                title: Text(suggestion.toString()),
              );
            },
            onSuggestionSelected: (suggestion) {
              birdSpecies = suggestion.toString();
              pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInCubic);
            },
            suggestionsCallback: (String pattern) {
              return _getSuggestions(pattern);
            },
          ),
          ButtonBar(
            alignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                  onPressed: () {
                    pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInCubic);
                  },
                  child: const Text("Back")),
              TextButton(
                  onPressed: () {
                    pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInCubic);
                  },
                  child: const Text("Review")),
            ],
          )
        ],
      );
    }

    Text confirmSubmission() {
      return Text("Cancel or Submit");
    }

    return PageView(
      controller: pageController,
      children: [verifyPhoto(), addSpecies(), confirmSubmission()],
    );
  }

  Stack takePhotoScreen() {
    return Stack(
      children: [
        StreamBuilder(
          builder: (context, snapshot) {
            return Center(child: CameraPreview(controller!));
          },
          stream: _cameraPreviewWidget().asStream(),
        ),
        _capturePhotoWidget(),
        // Opacity(opacity: 1, child: _capturePhotoWidget())
      ],
    );
  }

  Future<Widget> _cameraPreviewWidget() async {
    CameraController? cameraController = controller;
    try {
      await cameraController?.initialize();
    } on CameraException catch (e) {
      _handleFailedCameraInit(e);
    }
    return CameraPreview(
      cameraController!,
      child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails details) =>
              onViewFinderTap(details, constraints),
        );
      }),
    );
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Widget _capturePhotoWidget() {
    return Container(
      alignment: Alignment.bottomCenter,
      child: IconButton(
        icon: const Icon(
          Icons.camera_outlined,
        ),
        onPressed: onTakePictureButtonPressed,
      ),
    );
  }

  Future<void> onTakePictureButtonPressed() async {
    try {
      await controller?.initialize();
    } on CameraException catch (e) {
      _handleFailedCameraInit(e);
    }

    takePicture().then((XFile? file) {
      if (mounted && geoPosition != null) {
        setState(() {
          imageFile = file;
        });
        if (file != null) {
          // TODO Confirmation screen
          // TODO Upload to database
          showInSnackBar(
              'Picture saved to ${file.path} at ${geoPosition!.toString()} on ${geoPosition!.timestamp}');
        }
      }
    });
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      cameraController.dispose();
      return file;
    } on CameraException catch (e) {
      _logError(e.code, e.description);
      return null;
    }
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleFailedCameraInit(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        showInSnackBar('You have denied camera access.');
        break;
      case 'CameraAccessDeniedWithoutPrompt':
        // iOS only
        showInSnackBar('Please go to Settings app to enable camera access.');
        break;
      case 'CameraAccessRestricted':
        // iOS only
        showInSnackBar('Camera access is restricted.');
        break;
      default:
        _showCameraException(e);
        break;
    }
  }

  List<String> _getSuggestions(String pattern) {
    List<String> matches = [];
    matches.addAll(speciesList);
    matches.retainWhere((s) => s.toLowerCase().contains(pattern.toLowerCase()));
    return matches;
  }
}
