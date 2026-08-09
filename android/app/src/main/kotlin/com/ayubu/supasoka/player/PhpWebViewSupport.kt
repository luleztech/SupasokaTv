package com.ayubu.supasoka.player

/**
 * WebView helpers for PHP / gateway pages (EaMax phpStreamSupport.js).
 */
object PhpWebViewSupport {

    const val BROWSER_PLAYBACK_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36"

    /** [androidInterfaceName] must match [WebView.addJavascriptInterface] name (e.g. ShakaPlayerBridge). */
    fun gatewayPageRecoveryScript(androidInterfaceName: String = "ShakaPlayerBridge"): String {
        val postPlaying = """
          try {
            if (typeof $androidInterfaceName !== 'undefined' && $androidInterfaceName.onPlaybackStarted) {
              $androidInterfaceName.onPlaybackStarted();
            }
          } catch (e) {}
        """.trimIndent()

        return """
            (function () {
              var lastProgressAt = Date.now();
              var waitingSince = 0;
              var monitorStarted = false;

              function getVideo() {
                return document.querySelector('video');
              }

              function tryPlay(video) {
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
                video.controls = true;

                video.addEventListener('timeupdate', function () {
                  lastProgressAt = Date.now();
                  waitingSince = 0;
                });

                video.addEventListener('playing', function () {
                  lastProgressAt = Date.now();
                  waitingSince = 0;
                  $postPlaying
                });

                video.addEventListener('waiting', function () {
                  waitingSince = waitingSince || Date.now();
                });

                tryPlay(video);
              }

              function startMonitor() {
                if (monitorStarted) return;
                monitorStarted = true;
                setInterval(function () {
                  var video = getVideo();
                  if (!video) return;
                  bindVideo(video);

                  var now = Date.now();
                  var noProgressMs = now - lastProgressAt;
                  if (video.paused && !video.ended) {
                    tryPlay(video);
                  }

                  if ((video.readyState < 3 || video.seeking) && waitingSince === 0) {
                    waitingSince = now;
                  }

                  if (waitingSince > 0 && noProgressMs > 8000) {
                    try {
                      if (isFinite(video.currentTime) && video.currentTime > 0.15) {
                        video.currentTime = Math.max(0, video.currentTime - 0.1);
                      }
                    } catch (e) {}
                    tryPlay(video);
                    waitingSince = now;
                  }
                }, 2500);
              }

              try {
                var observer = new MutationObserver(function () {
                  var v = getVideo();
                  if (v) bindVideo(v);
                });
                observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
              } catch (e) {}

              bindVideo(getVideo());
              startMonitor();
              true;
            })();
        """.trimIndent()
    }
}
