// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:share/share.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String defaultLang =
      prefs.getString('defaultLang') ?? Platform.localeName.split('_')[0];
  runApp(MyApp(cameras: cameras, defaultLang: defaultLang));
}

 class dataModel {
  String photo;
  String lang;
  dataModel({required this.photo, required this.lang});
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final String defaultLang;

  const MyApp({super.key, required this.cameras, required this.defaultLang});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initLocalization(), // Initialize localization
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else {
          return MaterialApp(
            title: 'Take Photo App',
            theme: ThemeData(
              primarySwatch: Colors.blue,
            ),
            debugShowCheckedModeBanner: false,
            locale: Locale(defaultLang),
            supportedLocales: const [
              Locale('en'),
              Locale('ru'),
              Locale('uz'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: TakePhotoScreen(cameras: cameras),
          );
        }
      },
    );
  }

  Future<void> _initLocalization() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
}

class TakePhotoScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const TakePhotoScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _TakePhotoScreenState createState() => _TakePhotoScreenState();
}

class _TakePhotoScreenState extends State<TakePhotoScreen> {
  late CameraController _cameraController;
  File? _imageFile;
  final FlutterTts flutterTts = FlutterTts();
  bool _isCameraReady = false;
  bool _isSendingImage = false;
  String _selectedLanguage = 'en'; // Default selected language is English

  @override
  void initState() {
    super.initState();
    _initCamera();
    _setDefaultLanguage();
  }

  Future<void> _setDefaultLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage =
          prefs.getString('defaultLang') ?? Platform.localeName.split('_')[0];
    });
  }

  Future<void> _initCamera() async {
    _cameraController = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
    );
    await _cameraController.initialize();
    setState(() {
      _isCameraReady = true;
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      setState(() {
        _isSendingImage = true; // Start sending image
      });
      final XFile image = await _cameraController.takePicture();
      setState(() {
        _isSendingImage = false; // Finished sending image
        if (image != null) {
          _imageFile = File(image.path);
        }
      });

      // Send the image to the API if it's not null
      if (_imageFile != null) {
        final description =
            await _sendImageToAPI(_imageFile!, _selectedLanguage);

        // Navigate to the new page to display the taken image with the description
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DisplayImageScreen(
              imageFile: _imageFile!,
              imageDescription: description, // Pass imageDescription here
            ),
          ),
        );
      }
    } catch (e) {
      print('Error taking photo: $e');
      setState(() {
        _isSendingImage = false; // Error occurred while sending image
      });
    }
  }

  Future<String> _sendImageToAPI(File imageFile, String lang) async {
    try {
      var uri = Uri.parse(
          'http://44.204.66.45/generate_image_description/?lang=$lang');
      var request = http.MultipartRequest('POST', uri);

      // Attach the image file to the request
      var fileStream = http.ByteStream(imageFile.openRead());
      var length = await imageFile.length();
      var multipartFile = http.MultipartFile(
        'file',
        fileStream,
        length,
        filename: imageFile.path.split('/').last,
      );
      request.files.add(multipartFile);

      // Send the request
      var response = await request.send();

      // Handle response
      if (response.statusCode == 200) {
        // Successful API call
        final respStr = await response.stream.bytesToString();
        final jsonResponse = json.decode(respStr);
        final description = jsonResponse['iSee']; // Extracting the iSee value
        print('Image successfully sent to API.');
        print('API Response: $description');

        if (lang != 'uz') {
          _speakDescription(description, lang);
        } else {
          _convertTextToAudio(description);
        }
        return description;
      } else {
        // Error in API call
        print(
            'Failed to send image to API. Status code: ${response.statusCode}');
        final errorResponse = await response.stream.bytesToString();
        print('Error response: $errorResponse');
        return '';
      }
    } catch (e) {
      // Catch any exceptions
      print('Error: $e');
      return '';
    }
  }

  Future<void> _speakDescription(String description, String lang) async {
    try {
      // Set language for TTS
      await flutterTts.setLanguage(lang);

      // Speak the description
      await flutterTts.speak(description);
    } catch (e) {
      print('Error in TTS: $e');
    }
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  Future<void> _convertTextToAudio(String text) async {
    var url = "https://mohir.ai/api/v1/tts";
    var headers = {
      "Authorization":
          "d6551223-d914-4488-ad8c-050268b8d535:1fc2f5fb-5635-45ed-a43f-dfe1091bd43a",
      "Content-Type": "application/json",
    };

    var data = jsonEncode({
      "text": text,
      "model": "davron",
      "mood": "neutral",
      "blocking": "true",
      "webhook_notification_url": "",
    });

    try {
      var response =
          await http.post(Uri.parse(url), headers: headers, body: data);
      if (response.statusCode == 200) {
        print('Text converted to audio successfully.');
        var jsonResponse = json.decode(response.body);
        var audioUrl = jsonResponse['result']['url'];
        await _audioPlayer.play(UrlSource(audioUrl));
      } else {
        print(
            'Failed to convert text to audio. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error converting text to audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final navigationBarHeight = screenHeight * 0.30; // 30% of screen height
    final bodyHeight = screenHeight * 0.70; // 70% of screen height

    // Define language labels for accessibility
    final Map<String, String> languageAccessibilityLabels = {
      'en': 'English',
      'ru': 'Русский',
      'uz': 'Oʻzbekcha',
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        bottomOpacity: 0,
        elevation: 0,
        actions: [
          _buildLanguageAction(languageAccessibilityLabels['en']!, 'en'),
          SizedBox(width: 20),
          _buildLanguageAction(languageAccessibilityLabels['ru']!, 'ru'),
          SizedBox(width: 20),
          _buildLanguageAction(languageAccessibilityLabels['uz']!, 'uz'),
          SizedBox(width: 20),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              height: bodyHeight,
              child: Center(
                child: _isCameraReady
                    ? CameraPreview(_cameraController)
                    : CircularProgressIndicator(),
              ),
            ),
          ),
          Container(
            height: navigationBarHeight,
            color: Colors.blueGrey,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  color: Colors.red,
                  width: MediaQuery.of(context).size.width / 2,
                  height: double.infinity,
                  child: IconButton(
                    onPressed: () {
                      print('Call button pressed');
                    },
                    icon: Icon(Icons.phone, size: 50),
                    color: Colors.white,
                    tooltip: _selectedLanguage == 'ru'
                        ? 'Звонить'
                        : (_selectedLanguage == 'uz' ? 'Qoʻngʻiroq' : 'Call'),
                  ),
                ),
                Container(
                  color: _isCameraReady && !_isSendingImage
                      ? Colors.green
                      : Colors.grey,
                  width: MediaQuery.of(context).size.width / 2,
                  height: double.infinity,
                  child: IconButton(
                    onPressed:
                        _isCameraReady && !_isSendingImage ? _takePhoto : null,
                    icon: Icon(Icons.camera, size: 50),
                    color: Colors.white,
                    tooltip: _selectedLanguage == 'ru'
                        ? 'Снять фото'
                        : (_selectedLanguage == 'uz'
                            ? 'Rasm olmoq'
                            : 'Take a photo'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageAction(String label, String langCode) {
    return InkWell(
      onTap: () async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('defaultLang', langCode);
        setState(() {
          _selectedLanguage = langCode;
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Semantics(
          label: label, // Accessibility label
          child: Text(
            langCode.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 30,
              color:
                  _selectedLanguage == langCode ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class DisplayImageScreen extends StatefulWidget {
  final File imageFile;
  final String imageDescription;

  DisplayImageScreen(
      {Key? key, required this.imageFile, required this.imageDescription})
      : super(key: key);

  @override
  _DisplayImageScreenState createState() => _DisplayImageScreenState();
}

Future<void> deleteImage(String imageUri) async {
  final String baseUrl = "http://44.204.66.45"; // Use your actual base URL

  try {
    // Ensure the imageUri is properly encoded
    var encodedUri = Uri.encodeFull('$baseUrl/delete_image?photo=$imageUri');
    final response = await http.delete(Uri.parse(encodedUri));

    if (response.statusCode == 200) {
      // Successful deletion
      print('Image deleted successfully');
    } else {
      // Log different status codes or handle them as needed
      print('Deletion failed with status code: ${response.statusCode}');
      print('Response body: ${response.body}');
    }
  } catch (error) {
    // Handle specific exceptions if necessary
    print('Error while deleting image: $error');
    // Consider whether to re-throw the error depending on your error handling strategy
  }
}

class _DisplayImageScreenState extends State<DisplayImageScreen> {
  late TextEditingController _textEditingController;
  late List<Message> messages;
  late bool _isTyping;
  late AudioPlayer audioPlayer;
  final speechToText = SpeechToText();
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    initSpeechToText();
    _textEditingController = TextEditingController();
    messages = [];
    _isTyping = false;
    audioPlayer = AudioPlayer();
    messages.add(Message(text: widget.imageDescription, isOutgoing: false));
    _textEditingController.addListener(() {
      setState(() {
        _isTyping = _textEditingController.text.isNotEmpty;
      });
    });
  }

  Future<void> initSpeechToText() async {
    bool available = await speechToText.initialize();
    if (!available) {
      // Handle the case where Speech to Text is not available or initialization failed
      print('Speech to Text not available or initialization failed');
    }

    setState(() {});
  }

  void startListening() async {
    await speechToText.listen(onResult: onSpeechResult);
    setState(() {});
    print(_lastWords);
  }

  void stopListening() async {
    await speechToText.stop();
    setState(() {});
  }

  /// This is the callback that the SpeechToText plugin calls when
  /// the platform returns recognized words.
  void onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      print(_lastWords);
    });
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    audioPlayer.dispose();
    super.dispose();
    speechToText.stop();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Message copied to clipboard'),
    ));
  }

  Future<void> _stopSpeaking() async {
    final FlutterTts flutterTts = FlutterTts();
    await flutterTts.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0D1739),
      appBar: AppBar(
        title: const Text('Display and Share Image'),
        actions: [
          Semantics(
            label: 'Share', // Accessibility label
            child: IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => Share.shareFiles(
                [widget.imageFile.path],
                text: widget.imageDescription,
              ),
            ),
          ),
        ],
        leading: Semantics(
          label: 'Exit', // Accessibility label
          child: IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              _stopSpeaking();
              Navigator.pop(context);
              deleteImage(widget.imageFile.path).then((response) {
                print('Image deleted successfully');
              }).catchError((error) {
                print('Error deleting image: $error');
              });
            },
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              widget.imageFile,
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.cover,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return Align(
                  alignment: message.isOutgoing
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 15),
                          margin: const EdgeInsets.symmetric(
                              vertical: 5, horizontal: 8),
                          decoration: BoxDecoration(
                            color: message.isOutgoing
                                ? Colors.lightBlueAccent
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ),
                      if (!message.isOutgoing)
                        IconButton(
                          icon: Icon(Icons.copy, color: Colors.white),
                          onPressed: () => _copyToClipboard(message.text),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
            color: const Color(0xFF1C2031),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  onPressed: () {
                    _stopSpeaking();
                    Navigator.pop(context);
                    deleteImage(widget.imageFile.path).then((response) {
                      print('Image deleted successfully');
                    }).catchError((error) {
                      print('Error deleting image: $error');
                    });
                  },
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2031),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextField(
                      controller: _textEditingController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type your message here...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_isTyping ? Icons.send : Icons.keyboard_voice,
                      color:
                          speechToText.isListening ? Colors.red : Colors.white),
                  onPressed: _isTyping
                      ? () async {
                          setState(() {
                            messages.add(Message(
                                text: _textEditingController.text,
                                isOutgoing: true));
                            _textEditingController.clear();
                          });
                        }
                      : () async {
                          if (await speechToText.hasPermission &&
                              speechToText.isNotListening) {
                            startListening();
                            print(_lastWords);
                          } else if (speechToText.isListening) {
                            stopListening();
                          } else {
                            initSpeechToText();
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Message {
  String text;
  bool isOutgoing;
  Message({required this.text, required this.isOutgoing});
}
