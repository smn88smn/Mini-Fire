using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace MiniFire
{
    /// <summary>Google Sign-In + Firestore cloud profile sync.
    /// The Firebase / Google Sign-In SDKs are optional: all SDK calls sit behind
    /// the FIREBASE_SDK define. Without the SDK (or without firebase_config.json)
    /// the game runs fully offline — account features simply show a hint.
    /// SDK callbacks land on background threads; Pump() marshals them to the main thread.</summary>
    public static class CloudService
    {
        public static bool SdkPresent;
        public static bool Configured;
        public static string Uid = "", Email = "";
        public static string Status = "";
        public static bool Busy;
        public static event Action StateChanged;

        static readonly Queue<Action> mainThread = new Queue<Action>();
        static CloudConfig cfg;

        [Serializable]
        class CloudConfig
        {
            public string api_key = "";
            public string project_id = "";
            public string app_id = "";
            public string web_client_id = "";
        }

        static void Changed()
        {
            if (StateChanged != null) StateChanged();
        }

        /// <summary>Marshal a callback to the main thread (called from App.Update).</summary>
        static void OnMain(Action a) { lock (mainThread) mainThread.Enqueue(a); }

        public static void Pump()
        {
            Action[] batch;
            lock (mainThread)
            {
                batch = new Action[mainThread.Count];
                for (int i = 0; i < batch.Length; i++) batch[i] = mainThread.Dequeue();
            }
            foreach (var a in batch) { try { a(); } catch (Exception e) { Debug.LogWarning(e); } }
        }

        // ---------------- init ----------------

        public static void Init()
        {
#if FIREBASE_SDK
            SdkPresent = true;
#else
            SdkPresent = false;
#endif
            Uid = PlayerPrefs.GetString("cloud_uid", "");
            Email = PlayerPrefs.GetString("cloud_email", "");
            if (Application.platform != RuntimePlatform.Android) LoadConfigText(null);
            Status = Configured ? "" : "Cloud not configured";
        }

        /// <summary>Android: StreamingAssets is inside the APK — needs a web request.</summary>
        public static IEnumerator LoadConfigAsync()
        {
            if (Application.platform == RuntimePlatform.Android)
            {
                var path = Path.Combine(Application.streamingAssetsPath, "firebase_config.json");
                using (var req = UnityEngine.Networking.UnityWebRequest.Get(path))
                {
                    yield return req.SendWebRequest();
                    LoadConfigText(string.IsNullOrEmpty(req.error) ? req.downloadHandler?.text : null);
                }
            }
            else LoadConfigText(null);
            if (App.I != null) App.I.StartCoroutine(RealtimeDbDummy());
        }

        static IEnumerator RealtimeDbDummy() { yield break; }

        static void LoadConfigText(string json)
        {
            try
            {
                if (json == null)
                {
                    var path = Path.Combine(Application.streamingAssetsPath, "firebase_config.json");
                    if (File.Exists(path)) json = File.ReadAllText(path);
                }
                if (!string.IsNullOrEmpty(json))
                    cfg = JsonUtility.FromJson<CloudConfig>(json);
            }
            catch (Exception e) { Debug.LogWarning("cloud config read failed: " + e.Message); }
            Configured = cfg != null && !string.IsNullOrEmpty(cfg.api_key)
                && !string.IsNullOrEmpty(cfg.project_id) && !string.IsNullOrEmpty(cfg.web_client_id);
        }

        // ---------------- sign in / out ----------------

        public static bool SignedIn => !string.IsNullOrEmpty(Uid);

        public static void SignIn()
        {
            if (Busy) return;
            if (!SdkPresent) { Status = "Firebase SDK not installed (see docs)"; Changed(); return; }
            if (!Configured) { Status = "firebase_config.json missing (see docs)"; Changed(); return; }
            Busy = true;
            Status = "Signing in...";
            Changed();
            SignInSdk();
        }

#if FIREBASE_SDK
        static void SignInSdk()
        {
            try
            {
                // FirebaseApp: manual init from StreamingAssets config (no google-services.json needed)
                try
                {
                    var app = Firebase.FirebaseApp.DefaultInstance; // may throw if not yet created
                    if (app == null) throw new Exception("null");
                }
                catch
                {
                    var options = new Firebase.FirebaseAppOptions
                    {
                        ApiKey = cfg.api_key,
                        ProjectId = cfg.project_id,
                        ApplicationId = cfg.app_id,
                    };
                    Firebase.FirebaseApp.Create(options);
                }

                GoogleSignIn.Configuration = new GoogleSignInConfiguration
                {
                    WebClientId = cfg.web_client_id,
                    RequestIdToken = true,
                    RequestEmail = true,
                };
                GoogleSignIn.DefaultInstance.SignIn().ContinueWith(task =>
                {
                    if (task.IsFaulted || task.IsCanceled || task.Result == null)
                    {
                        OnMain(() => { Busy = false; Status = "Sign-in cancelled"; Changed(); });
                        return;
                    }
                    var idToken = task.Result.IdToken;
                    var credential = Firebase.Auth.GoogleAuthProvider.GetCredential(idToken, null);
                    Firebase.Auth.FirebaseAuth.DefaultInstance.SignInWithCredentialAsync(credential)
                        .ContinueWith(authTask => OnMain(() =>
                        {
                            Busy = false;
                            if (authTask.IsFaulted)
                            {
                                Status = "Firebase auth failed: " + authTask.Exception.GetBaseException().Message;
                                Changed();
                                return;
                            }
                            var user = authTask.Result;
                            Uid = user.UserId;
                            Email = user.Email ?? "";
                            PlayerPrefs.SetString("cloud_uid", Uid);
                            PlayerPrefs.SetString("cloud_email", Email);
                            Status = "Signed in";
                            Changed();
                            PullCloud();
                        }));
                });
            }
            catch (Exception e)
            {
                Busy = false;
                Status = "Sign-in error: " + e.Message;
                Changed();
            }
        }
#else
        static void SignInSdk() { Busy = false; }
#endif

        public static void SignOut()
        {
#if FIREBASE_SDK
            try
            {
                GoogleSignIn.DefaultInstance.SignOut();
                if (Firebase.Auth.FirebaseAuth.DefaultInstance != null &&
                    Firebase.Auth.FirebaseAuth.DefaultInstance.CurrentUser != null)
                    Firebase.Auth.FirebaseAuth.DefaultInstance.SignOut();
            }
            catch { }
#endif
            Uid = ""; Email = "";
            PlayerPrefs.DeleteKey("cloud_uid");
            PlayerPrefs.DeleteKey("cloud_email");
            Status = "Signed out";
            Changed();
        }

        // ---------------- sync ----------------

        public static void SyncNow()
        {
            if (!SignedIn) return;
            PullCloud();
        }

        static void PullCloud()
        {
#if FIREBASE_SDK
            Busy = true;
            Status = "Syncing...";
            Changed();
            try
            {
                var db = Firebase.Firestore.FirebaseFirestore.DefaultInstance;
                var doc = db.Collection(GameConfig.CloudCollection).Document(Uid);
                doc.GetSnapshotAsync().ContinueWith(task => OnMain(() =>
                {
                    Busy = false;
                    if (task.IsFaulted)
                    {
                        Status = "Sync failed: " + task.Exception.GetBaseException().Message;
                        Changed();
                        return;
                    }
                    var snap = task.Result;
                    if (snap.Exists)
                    {
                        var dict = new Dictionary<string, object>();
                        foreach (var kv in snap.ToDictionary()) dict[kv.Key] = kv.Value;
                        App.I.Profile.ApplyCloud(dict);
                        Status = "Cloud loaded";
                    }
                    else Status = "New account";
                    Changed();
                    PushCloud();
                }));
            }
            catch (Exception e)
            {
                Busy = false;
                Status = "Sync error: " + e.Message;
                Changed();
            }
#endif
        }

        public static void PushCloud()
        {
#if FIREBASE_SDK
            if (!SignedIn) return;
            try
            {
                var db = Firebase.Firestore.FirebaseFirestore.DefaultInstance;
                var doc = db.Collection(GameConfig.CloudCollection).Document(Uid);
                var snap = App.I.Profile.Snapshot();
                var plain = new Dictionary<string, object>();
                foreach (var kv in snap)
                {
                    if (kv.Value is Dictionary<string, int> d)
                    {
                        var dd = new Dictionary<string, object>();
                        foreach (var kv2 in d) dd[kv2.Key] = (long)kv2.Value;
                        plain[kv.Key] = dd;
                    }
                    else if (kv.Value is int i) plain[kv.Key] = (long)i;
                    else plain[kv.Key] = kv.Value;
                }
                doc.SetAsync(plain);
                Status = "Saved to cloud";
                Changed();
            }
            catch (Exception e) { Debug.LogWarning("push failed: " + e.Message); }
#endif
        }

        /// <summary>Upload the profile now (call after purchases / matches).</summary>
        public static void AutoSync()
        {
            if (SignedIn && !Busy) PushCloud();
        }
    }
}
