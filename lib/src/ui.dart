library ui;

import 'dart:async' show StreamSubscription;
import 'dart:html';

import 'package:pixelcycle2/src/movie.dart' show WIDTH, HEIGHT, LARGE, ALL, Movie, Frame, Size;
import 'package:pixelcycle2/src/player.dart' show Player, PlayDrag;

void onLoad(Player player) {

  for (CanvasElement elt in queryAll('canvas[class="strip"]')) {
    var size = new Size(elt.attributes["data-size"]);
    bool vertical = elt.attributes["data-vertical"] == "true";
    new StripView(player, elt, size, vertical: vertical);
  }

  for (CanvasElement elt in queryAll('canvas[class="movie"]')) {
    var size = new Size(elt.attributes["data-size"]);
    new MovieView(player, elt, size);
  }
}

/// Pixels between frames in StripView.
const SPACER = 10;

/// A StripView shows a strip of movie frames with the current frame near the center.
class StripView {
  final Player player;
  final CanvasElement elt;
  final Size size;
  final bool vertical;
  int pixelsPerFrame;
  int center;
  Frame _frame;
  StreamSubscription _frameSub;
  int _animSub;
  PlayDrag _drag;

  StripView(this.player, this.elt, this.size, {this.vertical: false}) {
    elt.style.backgroundColor = "#000000";
    var mouseFramePos;
    var touchFramePos;
    if (vertical) {
      elt.width = size.width + SPACER * 2;
      elt.height = LARGE.height;
      pixelsPerFrame = size.height + SPACER;
      center = elt.height ~/ 2;
      mouseFramePos = (MouseEvent e) => e.client.y / pixelsPerFrame;
      touchFramePos = (Touch t) => t.page.y / pixelsPerFrame;
    } else {
      elt.width = LARGE.width;
      elt.height = size.height + SPACER * 2;
      pixelsPerFrame = size.width + SPACER;
      center = elt.width ~/ 2;
      mouseFramePos = (MouseEvent e) => e.client.x / pixelsPerFrame;
      touchFramePos = (Touch t) => t.page.y / pixelsPerFrame;
    }

    player.onChange.listen((e) {
      renderAsync();
    });

    elt.onMouseDown.listen((e) {
      e.preventDefault();
      if (_drag == null) {
        var moveSub = elt.onMouseMove.listen((e) => _drag.update(mouseFramePos(e)));
        _drag = new PlayDrag.start(player, moveSub, mouseFramePos(e));
      }
    });

    elt.onMouseUp.listen((e) => _finishDrag());
    elt.onMouseOut.listen((e) => _finishDrag());
    query("body").onMouseUp.listen((e) => _finishDrag());

    elt.onTouchStart.listen((TouchEvent e) {
      print("onTouchStart");
      e.preventDefault();
      if (_drag == null) {
        var moveSub = elt.onTouchMove.listen((e) {
          for (Touch t in e.changedTouches) {
            if (t.identifier == _drag.touchId) {
              _drag.update(touchFramePos(t));
            }
          }
        });
        Touch t = e.changedTouches[0];
        _drag = new PlayDrag.start(player, moveSub, touchFramePos(t), touchId: t.identifier);
      }
    });

    elt.onTouchEnd.listen((TouchEvent e) {
      if (e.touches.isEmpty) {
        _finishDrag();
      }
    });
  }

  void _finishDrag() {
    if (_drag != null) {
      _drag.finish();
      _drag = null;
    }
  }

  void renderAsync() {
    if (_animSub == null) {
      _animSub = window.requestAnimationFrame(_render);
    }
  }

  void _render(num millis) {
    _animSub = null;

    num moviePosition = player.positionAt(millis/1000);
    int currentFrame = moviePosition ~/ 1;
    var movie = player.movie;

    elt.width = elt.width; // clear the canvas
    var c = elt.context2D;

    // movie position corresponding to the first displayed frame
    num startPos = (moviePosition - center / pixelsPerFrame) % movie.frames.length;

    int frame = startPos ~/ 1;
    // frame position in pixels from left or top.
    int framePos = ((frame - startPos) * pixelsPerFrame) ~/ 1 + SPACER ~/ 2;
    int endPos = vertical ? elt.height : elt.width;
    while (framePos < endPos) {
      // Set the alpha based on the distance from the center. (Proportional to total size.)
      var alphaDist = (framePos - center).abs() / (center * 2);
      c.globalAlpha = 0.8 - alphaDist * 0.6;
      if (vertical) {
        movie.frames[frame].renderAt(c, size, SPACER, framePos);
      } else {
        movie.frames[frame].renderAt(c, size, framePos, SPACER);
      }
      frame = (frame + 1) % movie.frames.length;
      framePos += pixelsPerFrame;
    }

    // Draw a line indicating the current frame
    c.strokeStyle = "#FFF";
    c.globalAlpha = 1.0;
    if (vertical) {
      c.moveTo(0, center);
      c.lineTo(elt.width, center);
      c.stroke();
    } else {
      c.moveTo(center, 0);
      c.lineTo(center, elt.height);
      c.stroke();
    }

    if (player.playing) {
      renderAsync();
    }
    _watch(player.currentFrame);
  }

  void _watch(Frame newFrame) {
    if (_frame == newFrame) {
      return;
    }
    _frame = newFrame;
    if (_frameSub != null) {
      _frameSub.cancel();
    }
    _frameSub = _frame.onChange.listen((Rect r) => renderAsync());
  }
}

/// A MovieView shows the current frame of a movie (according to the player).
/// It renders whenever the frame changes (due to drawing) or the player's
/// current frame changes. It uses requestAnimationFrame to avoid drawing too
/// often.
class MovieView {
  final Player player;
  final CanvasElement elt;
  final Size size;
  Frame _frame; // The most recently rendered frame (being watched).
  StreamSubscription _frameSub;
  Rect _damage; // Area of the watched frame that needs re-rendering.
  int _animSub; // Non-null if a render was requested.
  int colorIndex = 1;

  StreamSubscription _moveSub;

  MovieView(this.player, this.elt, this.size) {
    print("moviesize: ${size.pixelsize}");
    elt.width = WIDTH * size.pixelsize;
    elt.height = HEIGHT * size.pixelsize;

    player.onChange.listen((e) {
      renderAsync(ALL);
    });

    elt.onMouseDown.listen((e) {
      e.preventDefault();
      if (_frame == null) {
        return;
      }
      _paint(e);
      colorIndex = (colorIndex + 1) % 50;
      _moveSub = elt.onMouseMove.listen(_paint);
    });

    query("body").onMouseUp.listen((MouseEvent e) {
      if (_moveSub != null) {
        _moveSub.cancel();
      }
    });

    elt.onMouseOut.listen((MouseEvent e) {
      if (_moveSub != null) {
        _moveSub.cancel();
      }
    });
  }

  void _paint(MouseEvent e) {
    int x = (e.offset.x / size.pixelsize).toInt();
    int y = (e.offset.y / size.pixelsize).toInt();
    _frame.set(x, y, colorIndex);
  }

  void renderAsync(Rect clip) {
    if (_damage == null) {
      _damage = clip;
    } else if (clip != null) {
      _damage = _damage.union(clip);
    }
    if (_animSub == null) {
      _animSub = window.requestAnimationFrame(_render);
    }
  }

  /// Render the player's currently watched frame if needed.
  void _render(t) {
    _animSub = null;
    _watch(player.currentFrame);
    if (_damage != null) {
      _frame.render(elt.context2D, size, _damage);
      _damage = null;
    }
    if (player.playing) {
      renderAsync(null);
    }
  }

  /// Change the currently watched frame, updating the frame subscription if needed.
  void _watch(Frame newFrame) {
    if (_frame == newFrame) {
      return;
    }
    _frame = newFrame;
    if (_frameSub != null) {
      _frameSub.cancel();
    }
    _frameSub = _frame.onChange.listen(renderAsync);
    _frame.render(elt.context2D, size, ALL);
    _damage = null;
  }
}
