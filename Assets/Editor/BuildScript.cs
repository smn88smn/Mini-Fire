using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace MiniFire.EditorTools
{
    /// <summary>CI build entry point (-executeMethod MiniFire.EditorTools.BuildScript.BuildAndroid).
    /// Applies all Android settings programmatically so the repo needs no ProjectSettings
    /// beyond the defaults, then builds Builds/MiniFire.apk.</summary>
    public static class BuildScript
    {
        const string ScenePath = "Assets/Scenes/Main.unity";
        const string ApkPath = "Builds/MiniFire.apk";

        public static void BuildAndroid()
        {
            EnsureScene();
            ApplySettings();
            bool ok = RunBuild();
            EditorApplication.Exit(ok ? 0 : 1);
        }

        static void EnsureScene()
        {
            if (!File.Exists(ScenePath))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, ScenePath);
                Debug.Log("created scene " + ScenePath);
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        }

        static void ApplySettings()
        {
            PlayerSettings.companyName = "Saman";
            PlayerSettings.productName = "Mini Fire";

            var android = NamedBuildTarget.Android;
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "com.smn.minifire");
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.forceInternetPermission = true;
            PlayerSettings.Android.buildApkPerCpuArchitecture = false;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.SetApiCompatibilityLevel(android, ApiCompatibilityLevel.NET_Unity_4_8);
            PlayerSettings.stripEngineCode = true;

            // keystore (committed — private repo — so every CI build is signed identically;
            // the stable SHA-1 is required for Firebase Google Sign-In)
            const string ks = "Assets/Plugins/Android/minifire.keystore";
            if (File.Exists(ks))
            {
                PlayerSettings.Android.useCustomKeystore = true;
                PlayerSettings.Android.keystoreName = ks;
                PlayerSettings.Android.keystorePass = "MiniFire2026!";
                PlayerSettings.Android.keyaliasName = "minifire";
                PlayerSettings.Android.keyaliasPass = "MiniFire2026!";
            }
            else
            {
                Debug.LogWarning("keystore missing — debug signing will be used");
            }

            // Firebase: enable the FIREBASE_SDK define when the SDK was imported
            bool hasFirebase = Type.GetType("Firebase.FirebaseApp, Firebase.App") != null
                || Directory.Exists("Assets/Firebase");
            string defines = PlayerSettings.GetScriptingDefineSymbols(android);
            if (hasFirebase && !defines.Split(';').Contains("FIREBASE_SDK"))
            {
                defines = string.IsNullOrEmpty(defines) ? "FIREBASE_SDK" : defines + ";FIREBASE_SDK";
                PlayerSettings.SetScriptingDefineSymbols(android, defines);
                Debug.Log("FIREBASE_SDK define enabled");
            }
            Debug.Log("Firebase SDK detected: " + hasFirebase);
        }

        static bool RunBuild()
        {
            var options = new BuildPlayerOptions
            {
                scenes = EditorBuildSettings.scenes.Select(s => s.path).ToArray(),
                target = BuildTarget.Android,
                locationPathName = ApkPath,
                options = BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(options);
            var summary = report.summary;
            Debug.Log($"build result: {summary.result}, size: {summary.totalSize} bytes");
            if (summary.result == BuildResult.Succeeded) return true;
            foreach (var step in report.steps)
                if (step.messages.Any(m => m.type == LogType.Error || m.type == LogType.Exception))
                    Debug.LogError("step failed: " + step.name);
            return false;
        }
    }
}
