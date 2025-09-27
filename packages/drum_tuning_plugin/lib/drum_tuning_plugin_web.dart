import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/web/drum_tuning_web.dart';

/// Registers the web implementation of the drum tuning plugin.
void registerWith(Registrar registrar) {
  DrumTuningWeb.registerWith(registrar);
  registrar.registerMessageHandler();
}
