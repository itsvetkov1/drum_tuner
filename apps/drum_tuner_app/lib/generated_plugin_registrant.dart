// ignore_for_file: type=lint

import 'package:drum_tuning_plugin/drum_tuning_plugin_web.dart'
    as drum_tuning_plugin_web;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:record_web/record_web.dart';

void registerPlugins(Registrar registrar) {
  drum_tuning_plugin_web.registerWith(registrar);
  RecordPluginWeb.registerWith(registrar);
  registrar.registerMessageHandler();
}
