using System;
using UnityEngine;
using UnityEngine.UI;

namespace MiniFire
{
    /// <summary>Account screen: Google Sign-In with the account picker, cloud sync.</summary>
    public class AccountUI : Screen
    {
        Text status, email, uidText, hint, statusIn;
        RectTransform signedOutCard, signedInCard;
        float refresh;

        public AccountUI(App app, Canvas canvas) : base(app, canvas) { }

        protected override void OnBuild()
        {
            var rt = (RectTransform)root.transform;
            var win = UIFactory.Rect(rt, "account");
            win.StretchFull();
            UIFactory.Image(win, "bg", new Color(0.08f, 0.10f, 0.14f)).rectTransform.StretchFull();

            var header = UIFactory.Rect(win, "header");
            header.anchorMin = new Vector2(0, 1); header.anchorMax = new Vector2(1, 1);
            header.sizeDelta = new Vector2(0, 70);
            var title = UIFactory.Title(header, "ACCOUNT", 34);
            title.rectTransform.anchoredPosition = new Vector2(0, -35);
            var back = UIFactory.Button(header, "<", UIFactory.ButtonBgRed, new Vector2(56, 48), app.ShowMenu, 28);
            back.transform.localPosition = new Vector3(-600, -35, 0);

            // ---- signed-out card ----
            signedOutCard = UIFactory.Rect(win, "card_out");
            signedOutCard.sizeDelta = new Vector2(640, 420);
            var googleBtn = UIFactory.Button(signedOutCard, "Sign in with Google", UIFactory.ButtonBgBlue,
                new Vector2(380, 64), () => { CloudService.SignIn(); }, 26);
            googleBtn.transform.localPosition = new Vector3(0, 40, 0);
            hint = UIFactory.Label(signedOutCard,
                "Sign in with your Google account to save your progress in the cloud.\n" +
                "If you reinstall the game, sign in again to restore everything:\n" +
                "currencies, gun levels, characters, skins and powers.",
                20, UIFactory.TextDim, TextAnchor.UpperCenter);
            hint.rectTransform.StretchFull();
            hint.rectTransform.offsetMin = new Vector2(40, 130);
            hint.rectTransform.offsetMax = new Vector2(-40, -130);
            status = UIFactory.Label(signedOutCard, "", 18, UIFactory.Accent, TextAnchor.MiddleCenter);
            status.rectTransform.anchorMin = new Vector2(0.5f, 0); status.rectTransform.anchorMax = new Vector2(0.5f, 0);
            status.rectTransform.anchoredPosition = new Vector2(0, 60);
            status.name = "status_out";

            // ---- signed-in card ----
            signedInCard = UIFactory.Rect(win, "card_in");
            signedInCard.sizeDelta = new Vector2(640, 420);
            var okIcon = UIFactory.ImageSprite(signedInCard, "ok", "Art/icon_login");
            okIcon.rectTransform.sizeDelta = new Vector2(80, 80);
            okIcon.rectTransform.anchoredPosition = new Vector2(0, -40);
            email = UIFactory.Label(signedInCard, "", 26, UIFactory.TextMain, TextAnchor.MiddleCenter, FontStyle.Bold);
            email.rectTransform.anchorMin = new Vector2(0.5f, 0.5f); email.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            email.rectTransform.anchoredPosition = new Vector2(0, -30);
            uidText = UIFactory.Label(signedInCard, "", 16, UIFactory.TextDim, TextAnchor.MiddleCenter);
            uidText.rectTransform.anchorMin = new Vector2(0.5f, 0.5f); uidText.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            uidText.rectTransform.anchoredPosition = new Vector2(0, -62);
            var syncBtn = UIFactory.Button(signedInCard, "SYNC NOW", UIFactory.ButtonBgGreen, new Vector2(220, 56),
                () => CloudService.SyncNow(), 22);
            syncBtn.transform.localPosition = new Vector3(0, -110, 0);
            var outBtn = UIFactory.Button(signedInCard, "SIGN OUT", UIFactory.ButtonBgRed, new Vector2(220, 56),
                () => CloudService.SignOut(), 22);
            outBtn.transform.localPosition = new Vector3(0, -180, 0);
            statusIn = UIFactory.Label(signedInCard, "", 18, UIFactory.Accent, TextAnchor.MiddleCenter);
            statusIn.rectTransform.anchorMin = new Vector2(0.5f, 0); statusIn.rectTransform.anchorMax = new Vector2(0.5f, 0);
            statusIn.rectTransform.anchoredPosition = new Vector2(0, 60);
            statusIn.name = "status_in";

            CloudService.StateChanged -= Refresh;
            CloudService.StateChanged += Refresh;
            Refresh();
        }

        protected override void OnClose()
        {
            CloudService.StateChanged -= Refresh;
        }

        void Refresh()
        {
            bool in_ = CloudService.SignedIn;
            signedOutCard.gameObject.SetActive(!in_);
            signedInCard.gameObject.SetActive(in_);
            if (in_)
            {
                email.text = CloudService.Email;
                uidText.text = "UID: " + CloudService.Uid.Substring(0, Math.Min(14, CloudService.Uid.Length)) + "...";
            }
            string st = CloudService.Busy ? "Working..." : CloudService.Status;
            status.text = st;
            statusIn.text = st;
        }

        public override void Pump()
        {
            refresh += Time.unscaledDeltaTime;
            if (refresh > 1f) { refresh = 0; Refresh(); }
        }
    }
}
