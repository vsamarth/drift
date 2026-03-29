import 'package:flutter/widgets.dart';

import 'app/drift_app.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const DriftApp());
}
