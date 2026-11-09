using System;
using System.Collections.Generic;
using UnityEngine;

namespace MiniFire
{
    /// <summary>App bootstrap: owns the profile, the UI canvas and the game flow
    /// (menu -> lobby -> match -> results). Attached to the single scene object.</summary>
    public class App : MonoBehaviour
    {
        public static App I { get; private set; }

        public ProfileService Profile { get; private set; }
        public MatchRunner Match => MatchRunner.I;

        Canvas ui;
        Screen current;

        void Awake()
        {
            if (I != null) { Destroy(gameObject); return; }
            I = this;
            DontDestroyOnLoad(gameObject);

            Profile = new ProfileService();
            Sfx.Init();
            Sfx.SetVolume(Profile.D.sfx_volume);
            NetSession.Init();
            CloudService.Init();

            ui = UIFactory.CreateRootCanvas("UICanvas");
            UIFactory.EnsureEventSystem();
            StartCoroutine(CloudService.LoadConfigAsync());
        }

        void Start()
        {
            ShowMenu();
        }

        void Update()
        {
            NetSession.I.Pump();
            Effects.Pump();
            CloudService.Pump();
            if (current != null) current.Pump();
        }

        void OnDestroy()
        {
            if (I == this) I = null;
        }

        // ---------------- flow ----------------

        public void ShowMenu()
        {
            TouchInput.Destroy();
            SetScreen(new MainMenuUI(this, ui));
        }

        public void OpenShop() => SetScreen(new ShopUI(this, ui));
        public void OpenSpinShop() => SetScreen(new SpinShopUI(this, ui));
        public void OpenAccount() => SetScreen(new AccountUI(this, ui));
        public void OpenLobbyOnline() => SetScreen(new LobbyUI(this, ui, true));
        public void OpenLobbyPractice() => SetScreen(new LobbyUI(this, ui, false));

        /// <summary>Called by LobbyUI (host/offline) or NetSession.MatchStarted (client).</summary>
        public void BeginMatch(MatchStartInfo info, bool online, bool isHost)
        {
            TouchInput.Destroy();
            SetScreen(null);
            MatchRunner.Begin(info, online, isHost);
            var hud = new MatchHUD(this, ui);
            SetScreen(hud);
            Sfx.Play("sfx_start");
        }

        void SetScreen(Screen s)
        {
            if (current != null) current.Close();
            current = s;
            if (current != null) current.Build();
        }

        public void Toast(string msg) => UIFactory.Toast(ui.transform, msg);

        // ---------------- scene bootstrap ----------------

        /// <summary>Creates the App object even in an empty scene, so the build
        /// does not depend on scene contents.</summary>
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Bootstrap()
        {
            if (I == null)
            {
                var go = new GameObject("App");
                DontDestroyOnLoad(go);
                go.AddComponent<App>();
            }
        }

        public static void EnsureCamera()
        {
            if (Camera.main == null)
            {
                var cam = new GameObject("MainCamera", typeof(Camera), typeof(AudioListener));
                cam.tag = "MainCamera";
                cam.transform.position = new Vector3(32, 18, -10);
                var c = cam.GetComponent<Camera>();
                c.orthographic = true;
                c.orthographicSize = 10f;
                c.backgroundColor = new Color(0.1f, 0.12f, 0.18f);
            }
        }
    }

    /// <summary>Base class for menu screens built procedurally.</summary>
    public abstract class Screen
    {
        protected App app;
        protected Canvas canvas;
        protected GameObject root;

        protected Screen(App app, Canvas canvas)
        {
            this.app = app;
            this.canvas = canvas;
        }

        public void Build()
        {
            root = new GameObject("screen_" + GetType().Name, typeof(RectTransform));
            root.transform.SetParent(canvas.transform, false);
            ((RectTransform)root.transform).StretchFull();
            OnBuild();
        }

        public void Close()
        {
            if (root != null) UnityEngine.Object.Destroy(root);
            OnClose();
        }

        public virtual void Pump() { }
        protected virtual void OnBuild() { }
        protected virtual void OnClose() { }
    }
}
