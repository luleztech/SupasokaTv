/// Injected after gateway pages load — adapted from `/player/PhpWebViewSupport.kt`
/// (video element recovery; Android JS bridge calls removed).
const String kPhpGatewayRecoveryJs = '''
(function () {
  if (window.__eaMaxRecoveryInstalled) { return true; }
  window.__eaMaxRecoveryInstalled = true;

  var lastNudgeAt = 0;

  /** Wait for a real checkbox token — never stub/hide (that stuck users forever). */
  function patchRecaptchaExecute() {
    try {
      if (window.__supasokaSilentCaptcha) return;
      if (window.__supasokaCaptchaFix) return;
      window.__supasokaCaptchaFix = true;
      function readToken() {
        var token = '';
        try {
          if (window.grecaptcha && typeof grecaptcha.getResponse === 'function') {
            token = grecaptcha.getResponse() || '';
            if (!token) {
              for (var i = 0; i < 8; i++) {
                try { token = grecaptcha.getResponse(i) || ''; if (token) break; } catch (e) {}
              }
            }
          }
        } catch (e) {}
        return token || '';
      }
      function patch() {
        try {
          if (!window.grecaptcha || typeof grecaptcha.execute !== 'function') return false;
          if (grecaptcha.__supasokaPatched) return true;
          var orig = grecaptcha.execute.bind(grecaptcha);
          grecaptcha.execute = function(siteKey, opts) {
            try {
              var el = document.querySelector('.g-recaptcha');
              var size = (el && el.getAttribute('data-size')) || '';
              if (size === 'invisible') return orig(siteKey, opts);
              var existing = readToken();
              if (existing) return Promise.resolve(existing);
              return new Promise(function(resolve, reject) {
                var n = 0;
                var t = setInterval(function() {
                  n++;
                  var token = readToken();
                  if (token) { clearInterval(t); resolve(token); }
                  else if (n > 360) { clearInterval(t); reject(new Error('captcha_timeout')); }
                }, 500);
              });
            } catch (e) {
              return orig(siteKey, opts);
            }
          };
          grecaptcha.__supasokaPatched = true;
          return true;
        } catch (e) { return false; }
      }
      if (!patch()) {
        var iv = setInterval(function() { if (patch()) clearInterval(iv); }, 400);
        setTimeout(function() { clearInterval(iv); }, 45000);
      }
    } catch (e) {}
  }

  function getVideo() {
    return document.querySelector('video');
  }

  function muteSecondaryVideos() {
    try {
      var vids = document.querySelectorAll('video');
      if (!vids || vids.length <= 1) return;
      var primary = null, best = -1;
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        var score = (v.clientWidth || 0) * (v.clientHeight || 0);
        if (!v.paused && !v.ended) score += 1000000000;
        if (score > best) { best = score; primary = v; }
      }
      for (var j = 0; j < vids.length; j++) {
        if (vids[j] === primary) {
          try { vids[j].muted = false; } catch (e0) {}
        } else {
          try { vids[j].muted = true; vids[j].pause(); } catch (e1) {}
        }
      }
    } catch (e) {}
  }

  function tryPlay(video) {
    if (!video || window.__eaMaxPlaybackLocked) return;
    if (!video.paused || video.ended) return;
    if (video.readyState < 2) return;
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
      patchRecaptchaExecute();
      muteSecondaryVideos();
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
      patchRecaptchaExecute();
      muteSecondaryVideos();
      if (window.__eaMaxPlaybackLocked) return;
      var v = getVideo();
      if (v) bindVideo(v);
    });
    observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
  } catch (e) {}

  patchRecaptchaExecute();
  muteSecondaryVideos();
  bindVideo(getVideo());
  startMonitor();
  true;
})();
''';
