/// Injected after gateway pages load — adapted from `/player/PhpWebViewSupport.kt`
/// (video element recovery; Android JS bridge calls removed).
const String kPhpGatewayRecoveryJs = '''
(function () {
  if (window.__eaMaxRecoveryInstalled) { return true; }
  window.__eaMaxRecoveryInstalled = true;

  var lastNudgeAt = 0;

  function hideCaptchaOverlays() {
    try {
      var nodes = document.querySelectorAll(
        '.g-recaptcha, .grecaptcha-badge, iframe[src*="recaptcha"], iframe[src*="google.com/recaptcha"], #captcha, .cf-challenge, .cf-browser-verification'
      );
      for (var i = 0; i < nodes.length; i++) {
        try {
          nodes[i].style.setProperty('display', 'none', 'important');
          nodes[i].style.setProperty('visibility', 'hidden', 'important');
          nodes[i].style.setProperty('pointer-events', 'none', 'important');
        } catch (e) {}
      }
      var style = document.getElementById('__supasoka_hide_captcha');
      if (!style) {
        style = document.createElement('style');
        style.id = '__supasoka_hide_captcha';
        style.textContent = '.g-recaptcha,.grecaptcha-badge,iframe[src*="recaptcha"],.cf-challenge{display:none!important;visibility:hidden!important;pointer-events:none!important}';
        (document.head || document.documentElement).appendChild(style);
      }
    } catch (e) {}
  }

  function getVideo() {
    return document.querySelector('video');
  }

  function tryPlay(video) {
    if (!video || window.__eaMaxPlaybackLocked) return;
    if (!video.paused || video.ended) return;
    try {
      var p = video.play && video.play();
      if (p && typeof p.catch === 'function') p.catch(function(){});
    } catch (e) {}
  }

  function bindVideo(video) {
    if (!video || video.__nixBound) return;
    video.__nixBound = true;
    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');
    try { video.muted = false; } catch (e) {}
    video.controls = false;
    video.removeAttribute('controls');

    video.addEventListener('playing', function () {
      window.__eaMaxPlaybackLocked = true;
      try {
        if (window.SupasokaPlayback && SupasokaPlayback.postMessage) {
          SupasokaPlayback.postMessage('playing');
        }
      } catch (e) {}
    });

    if (!window.__eaMaxPlaybackLocked) tryPlay(video);
  }

  function startMonitor() {
    setInterval(function () {
      hideCaptchaOverlays();
      if (window.__eaMaxPlaybackLocked) return;
      var video = getVideo();
      if (!video || video.ended || !video.paused) return;
      bindVideo(video);
      var now = Date.now();
      if (now - lastNudgeAt > 8000) {
        tryPlay(video);
        lastNudgeAt = now;
      }
    }, 5000);
  }

  try {
    var observer = new MutationObserver(function () {
      hideCaptchaOverlays();
      if (window.__eaMaxPlaybackLocked) return;
      var v = getVideo();
      if (v) bindVideo(v);
    });
    observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
  } catch (e) {}

  hideCaptchaOverlays();
  bindVideo(getVideo());
  startMonitor();
  true;
})();
''';
