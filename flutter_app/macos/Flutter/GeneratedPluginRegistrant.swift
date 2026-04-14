//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_session
import file_selector_macos
import package_info_plus
import record_macos
import share_plus
import shared_preferences_foundation
import sign_in_with_apple

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  RecordMacOsPlugin.register(with: registry.registrar(forPlugin: "RecordMacOsPlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  SignInWithApplePlugin.register(with: registry.registrar(forPlugin: "SignInWithApplePlugin"))
}
