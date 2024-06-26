import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:js_interop';
import 'dart:js_util';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:webrtc_interface/webrtc_interface.dart';

import 'rtc_video_renderer_impl.dart';

class RTCVideoView extends StatefulWidget {
  RTCVideoView(
    this._renderer, {
    Key? key,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    this.mirror = false,
    this.filterQuality = FilterQuality.low,
    this.placeholderBuilder,
  }) : super(key: key);

  final RTCVideoRenderer _renderer;
  final RTCVideoViewObjectFit objectFit;
  final bool mirror;
  final FilterQuality filterQuality;
  final WidgetBuilder? placeholderBuilder;

  @override
  RTCVideoViewState createState() => RTCVideoViewState();
}

class RTCVideoViewState extends State<RTCVideoView> {
  RTCVideoViewState();

  RTCVideoRenderer get videoRenderer => widget._renderer;

  @override
  void initState() {
    super.initState();
    videoRenderer.addListener(_onRendererListener);
    videoRenderer.mirror = widget.mirror;
    videoRenderer.objectFit =
        widget.objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
            ? 'contain'
            : 'cover';
    frameCallback(0.toJS, 0.toJS);
  }

  void _onRendererListener() {
    if (mounted) setState(() {});
  }

  int? callbackID;

  void getFrame(web.HTMLVideoElement element) {
    callbackID =
        element.requestVideoFrameCallbackWithFallback(frameCallback.toJS);
  }

  void cancelFrame(web.HTMLVideoElement element) {
    if (callbackID != null) {
      element.cancelVideoFrameCallbackWithFallback(callbackID!);
    }
  }

  void frameCallback(JSAny now, JSAny metadata) {
    final web.HTMLVideoElement? element = videoElement;
    if (element != null) {
      // only capture frames if video is playing (optimization for RAF)
      if (element.readyState > 2) {
        capture().then((_) async {
          getFrame(element);
        });
      } else {
        getFrame(element);
      }
    } else {
      if (mounted) {
        Future.delayed(Duration(milliseconds: 100)).then((_) {
          frameCallback(0.toJS, 0.toJS);
        });
      }
    }
  }

  ui.Image? capturedFrame;
  num? lastFrameTime;
  Future<void> capture() async {
    final element = videoElement!;
    if (lastFrameTime != element.currentTime) {
      lastFrameTime = element.currentTime;
      try {
        final ui.Image img = await ui_web.createImageFromTextureSource(element,
            width: element.videoWidth,
            height: element.videoHeight,
            transferOwnership: false);

        if (mounted) {
          setState(() {
            capturedFrame?.dispose();
            capturedFrame = img;
          });
        }
      } on web.DOMException catch (err) {
        lastFrameTime = null;
        if (err.name == 'InvalidStateError') {
          // We don't have enough data yet, continue on
        } else {
          rethrow;
        }
      }
    }
  }

  @override
  void dispose() {
    if (mounted) {
      super.dispose();
    }
    if (videoElement != null) {
      cancelFrame(videoElement!);
    }
  }

  @override
  void didUpdateWidget(RTCVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    Timer(
        Duration(milliseconds: 10), () => videoRenderer.mirror = widget.mirror);
    videoRenderer.objectFit =
        widget.objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
            ? 'contain'
            : 'cover';
  }

  web.HTMLVideoElement? videoElement;

  Widget buildVideoElementView() {
    if (useHtmlElementView) {
      return HtmlElementView(viewType: videoRenderer.viewType);
    } else {
      return Stack(children: [
        Positioned.fill(
            child: HtmlElementView(
                viewType: videoRenderer.viewType,
                onPlatformViewCreated: (viewId) {
                  videoElement = ui_web.platformViewRegistry.getViewById(viewId)
                      as web.HTMLVideoElement;
                })),
        if (capturedFrame != null)
          Positioned.fill(
              child: widget.mirror
                  ? Transform.flip(
                      flipX: true,
                      child: RawImage(
                          image: capturedFrame,
                          fit: switch (widget.objectFit) {
                            RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitContain =>
                              BoxFit.contain,
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover =>
                              BoxFit.cover,
                          }))
                  : RawImage(
                      image: capturedFrame,
                      fit: switch (widget.objectFit) {
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain =>
                          BoxFit.contain,
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover =>
                          BoxFit.cover,
                      })),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Center(
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: widget._renderer.renderVideo
                ? buildVideoElementView()
                : widget.placeholderBuilder?.call(context) ?? Container(),
          ),
        );
      },
    );
  }
}

typedef _VideoFrameRequestCallback = JSFunction;

extension _HTMLVideoElementRequestAnimationFrame on web.HTMLVideoElement {
  int requestVideoFrameCallbackWithFallback(
      _VideoFrameRequestCallback callback) {
    if (hasProperty(this, 'requestVideoFrameCallback')) {
      return requestVideoFrameCallback(callback);
    } else {
      return web.window.requestAnimationFrame((double num) {
        callback.callAsFunction(this, 0.toJS, 0.toJS);
      }.toJS);
    }
  }

  void cancelVideoFrameCallbackWithFallback(int callbackID) {
    if (hasProperty(this, 'requestVideoFrameCallback')) {
      cancelVideoFrameCallback(callbackID);
    } else {
      web.window.cancelAnimationFrame(callbackID);
    }
  }

  external int requestVideoFrameCallback(_VideoFrameRequestCallback callback);
  external void cancelVideoFrameCallback(int callbackID);
}
