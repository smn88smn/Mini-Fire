#
# © 2026-present https://github.com/firebase-team
#

@tool
extends EditorPlugin

const PLUGIN_NAME: String = "FirebasePlugin"
const ANDROID_DEPENDENCIES: Array = [ "androidx.appcompat:appcompat:1.7.1", "com.google.firebase:firebase-auth:24.0.1", "com.google.firebase:firebase-firestore:26.2.0", "com.google.android.gms:play-services-auth:21.5.1" ]

var android_export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	android_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(android_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(android_export_plugin)
	android_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:

	# Firebase plugin lines to inject into Gradle files
	const BUILD_GRADLE_PLUGIN_LINE := "id 'com.google.gms.google-services'"
	const SETTINGS_GRADLE_PLUGIN_LINE := "id 'com.google.gms.google-services' version '4.4.2' apply false"

	var _plugin_name = PLUGIN_NAME


	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid


	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["%s/bin/debug/%s-debug.aar" % [_plugin_name, _plugin_name]])
		else:
			return PackedStringArray(["%s/bin/release/%s-release.aar" % [_plugin_name, _plugin_name]])


	func _get_name() -> String:
		return _plugin_name


	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(ANDROID_DEPENDENCIES)

	func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
		if not features.has("android"):
			return

		if ((not get_option("gradle_build/use_gradle_build")) or
				(not FileAccess.file_exists("res://android/build/google-services.json"))):
			_clean_line_from_file("res://android/build/build.gradle", BUILD_GRADLE_PLUGIN_LINE)
			_clean_line_from_file("res://android/build/settings.gradle", SETTINGS_GRADLE_PLUGIN_LINE)
			return

		# Modify build.gradle and settings.gradle
		_insert_line_if_missing("res://android/build/build.gradle", "id 'org.jetbrains.kotlin.android'",
				BUILD_GRADLE_PLUGIN_LINE)
		_insert_line_if_missing(
				"res://android/build/settings.gradle", "id 'org.jetbrains.kotlin.android' version versions.kotlinVersion",
				SETTINGS_GRADLE_PLUGIN_LINE)


	func _insert_line_if_missing(file_path: String, after_line: String, insert_line: String) -> void:
		var text := FileAccess.open(file_path, FileAccess.READ).get_as_text()
		if text.contains(insert_line):
			return

		var lines := text.split("\n")
		var result := PackedStringArray()
		var inserted := false

		for line in lines:
			result.append(line)
			if not inserted and line.strip_edges() == after_line.strip_edges():
				var indent := ""
				for c in line:
					if c == " " or c == "\t":
						indent += c
					else:
						break
				result.append(indent + insert_line)
				inserted = true

		var file := FileAccess.open(file_path, FileAccess.WRITE)
		file.store_string("\n".join(result))
		file.close()


	func _clean_line_from_file(file_path: String, line_to_remove: String) -> void:
		if FileAccess.file_exists(file_path):
			var text := FileAccess.open(file_path, FileAccess.READ).get_as_text()
			text = text.replace(line_to_remove, "")
			var file := FileAccess.open(file_path, FileAccess.WRITE)
			file.store_string(text)
			file.close()
