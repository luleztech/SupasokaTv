package com.ayubu.supasoka.player

import android.content.Context
import android.graphics.Color
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/** WebView settings tuned for PHP gateways and Google reCAPTCHA challenges. */
object GatewayWebViewHelper {

    /** Chrome-like UA without the WebView `; wv` token — reCAPTCHA often blocks WebView UAs. */
    fun browserUserAgent(context: Context): String {
        val default = WebSettings.getDefaultUserAgent(context)
        return when {
            default.contains("; wv") -> default.replace("; wv", "")
            default.contains(" wv ") -> default.replace(" wv ", " ")
            else -> default
        }
    }

    fun applySettings(webView: WebView, context: Context, userAgent: String? = null) {
        webView.setBackgroundColor(Color.BLACK)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            allowFileAccessFromFileURLs = true
            allowUniversalAccessFromFileURLs = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            setSupportMultipleWindows(true)
            javaScriptCanOpenWindowsAutomatically = true
            loadWithOverviewMode = true
            useWideViewPort = true
            loadsImagesAutomatically = true
            blockNetworkImage = false
            cacheMode = WebSettings.LOAD_DEFAULT
            // Keep page at 100% — overview+zoom defaults often crop score bars.
            textZoom = 100
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            userAgentString = userAgent?.takeIf { it.isNotBlank() } ?: browserUserAgent(context)
        }
        webView.setInitialScale(100)
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
    }

    /**
     * Handles reCAPTCHA popups (`window.open`) by hosting a child WebView over the player container.
     */
    fun createChromeClient(
        hostWebView: WebView,
        onConsoleMessage: ((android.webkit.ConsoleMessage?) -> Unit)? = null,
    ): WebChromeClient {
        return object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message,
            ): Boolean {
                val popup = WebView(view.context)
                applySettings(popup, view.context, view.settings.userAgentString)
                popup.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        w: WebView,
                        request: android.webkit.WebResourceRequest,
                    ): Boolean = false
                }
                popup.webChromeClient = object : WebChromeClient() {
                    override fun onCloseWindow(window: WebView) {
                        dismissPopup(window)
                    }
                }
                val parent = view.parent as? ViewGroup
                    ?: (hostWebView.parent as? ViewGroup)
                    ?: return false
                parent.addView(
                    popup,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
                transport.webView = popup
                resultMsg.sendToTarget()
                return true
            }

            override fun onCloseWindow(window: WebView) {
                dismissPopup(window)
            }

            override fun onPermissionRequest(request: android.webkit.PermissionRequest?) {
                request?.grant(request.resources)
            }

            override fun onConsoleMessage(
                consoleMessage: android.webkit.ConsoleMessage?,
            ): Boolean {
                onConsoleMessage?.invoke(consoleMessage)
                return true
            }
        }
    }

    private fun dismissPopup(window: WebView) {
        (window.parent as? ViewGroup)?.removeView(window)
        window.stopLoading()
        window.destroy()
    }

    /** Returns `video` when a player element exists, `captcha` while reCAPTCHA is on screen. */
    const val PAGE_PROBE_JS = """
        (function(){
          try{
            if(document.querySelector('video')) return 'video';
            if(document.querySelector('iframe[src*="recaptcha"], iframe[src*="google.com/recaptcha"], .g-recaptcha, [data-sitekey]')) return 'captcha';
          }catch(e){}
          return 'waiting';
        })();
    """

    /**
     * Force video object-fit based on [window.__leotenaZoomMode]:
     * contain|normal → contain, fill → cover, stretched → fill.
     */
    fun zoomVideoJs(mode: String = "contain"): String {
        val safe = when (mode.lowercase().trim()) {
            "fill", "cover", "zoom" -> "fill"
            "stretched", "stretch" -> "stretched"
            "normal" -> "normal"
            else -> "contain"
        }
        return """
        (function(){
          window.__leotenaZoomMode='$safe';
          function fitFor(mode){
            if(mode==='fill') return 'cover';
            if(mode==='stretched') return 'fill';
            return 'contain';
          }
          function applyTo(doc){
            if(!doc) return;
            var fit = fitFor(window.__leotenaZoomMode||'contain');
            try{
              var styleId='__leotenaZoomCss';
              var s=doc.getElementById(styleId);
              if(!s){
                s=doc.createElement('style');
                s.id=styleId;
                (doc.head||doc.documentElement).appendChild(s);
              }
              s.textContent=[
                'html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:#000!important}',
                'video,.shaka-video,.video-js video{object-fit:'+fit+'!important;-webkit-object-fit:'+fit+'!important;width:100%!important;height:100%!important;max-width:100%!important;max-height:100%!important;background:#000!important}',
                '.shaka-video-container,.video-js,#player,.player{width:100%!important;height:100%!important;max-width:100%!important;max-height:100%!important;background:#000!important}',
                'header,nav,.navbar,.nav-bar,.top-bar,.topbar,.app-bar,.toolbar,.channel-title,.player-title,.stream-title,.back-btn,.back-button,[class*="back-button"],[class*="backBtn"],[id*="back"],.vjs-control-bar .vjs-title,[data-testid*="back"],.shaka-controls-button-panel .shaka-back-button{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;height:0!important;width:0!important;overflow:hidden!important}',
                '@media (orientation:landscape){video,.shaka-video,.shaka-video-container video{object-fit:'+fit+'!important;-webkit-object-fit:'+fit+'!important}}'
              ].join('');
              var vids=doc.querySelectorAll('video');
              for(var i=0;i<vids.length;i++){
                try{
                  vids[i].style.setProperty('object-fit',fit,'important');
                  vids[i].style.setProperty('width','100%','important');
                  vids[i].style.setProperty('height','100%','important');
                }catch(e1){}
              }
            }catch(e2){}
            try{
              var iframes=doc.querySelectorAll('iframe');
              for(var j=0;j<iframes.length;j++){
                try{
                  var idoc=iframes[j].contentDocument||(iframes[j].contentWindow&&iframes[j].contentWindow.document);
                  if(idoc) applyTo(idoc);
                }catch(e3){}
              }
            }catch(e4){}
          }
          applyTo(document);
          if(!window.__leotenaZoomTimer){
            window.__leotenaZoomTimer=setInterval(function(){ applyTo(document); }, 2000);
          }
        })();
        """.trimIndent()
    }

    /** @deprecated Prefer [zoomVideoJs]; kept for older inject call sites. */
    const val CONTAIN_VIDEO_JS = """
        (function(){
          window.__leotenaZoomMode=window.__leotenaZoomMode||'contain';
        })();
    """
}
