import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../painters/dial_painter.dart';

/// The dial, plus the gestures that act on it: tap a wedge to select it, drag a
/// shared boundary to rescale the two blocks that meet there (SPEC §2.4).
///
/// The widget owns no day state — it turns a touch into "this boundary, this
/// minute" and hands that up. Whether the move is legal (15-minute minimum,
/// can't cross a neighbor) is decided by `core` when the caller applies it.
///
/// With no callbacks wired it is a pure, stateless render — which is what the
/// golden tests pump, and why they see no drag handles.
class DialView extends StatefulWidget {
  const DialView({
    super.key,
    required this.profile,
    required this.nowMin,
    required this.mode,
    this.selectedSegmentId,
    this.onSegmentTapped,
    this.onBoundaryDragged,
    this.onBoundaryDragEnd,
    this.actuals = const [],
    this.overlay = const [],
    this.subBlocks = const SubBlockPlan.empty(),
    this.palette = DialPalette.dark,
  });

  final DayProfile profile;
  final int nowMin;
  final DialMode mode;
  final String? selectedSegmentId;

  /// Called with the tapped segment's id (null taps — the hub — are ignored).
  final ValueChanged<String>? onSegmentTapped;

  /// Called as a boundary is dragged, with the id of the block that **ends**
  /// there and the minute it should now end at (already snapped to a tidy
  /// step). Fires continuously during the drag; the caller applies each one and
  /// may reject it, which simply leaves the boundary where it was.
  final void Function(String segmentId, int endMin)? onBoundaryDragged;

  /// Called once when a boundary drag finishes — the moment to persist, or to
  /// reschedule anything keyed to the day's shape.
  final VoidCallback? onBoundaryDragEnd;

  /// Logged actuals to overlay on the inner ring.
  final List<ActualArc> actuals;

  /// Read-only calendar events, drawn on a concentric track outside the ring.
  final List<OverlayArc> overlay;

  /// Sparse sub-block overlay; the active/selected block subdivides into these.
  final SubBlockPlan subBlocks;
  final DialPalette palette;

  @override
  State<DialView> createState() => _DialViewState();
}

class _DialViewState extends State<DialView> {
  /// The block whose end boundary is under the finger, or null when not
  /// dragging.
  String? _dragging;

  /// Whether the claimed pointer actually moved. A grab that never moves is a
  /// tap, and has to select the wedge — see [_onPanEnd].
  bool _moved = false;

  Size _size = Size.zero;

  bool get _editable => widget.onBoundaryDragged != null;

  DialGeometry get _geometry =>
      DialGeometry(size: _size, mode: widget.mode, nowMin: widget.nowMin);

  /// Whether a touch at [local] is a grab at a shared boundary. Answered at
  /// pointer-down, because that decides whether this gesture belongs to the
  /// dial or to the page scrolling behind it.
  bool _grabAt(Offset local) =>
      _editable &&
      _geometry.isOnRing(local) &&
      widget.profile.boundaryNear(_geometry.minuteAt(local)) != null;

  void _select(Offset local) {
    final onTap = widget.onSegmentTapped;
    if (onTap == null) return;
    onTap(widget.profile.segmentAt(_geometry.minuteAt(local)).id);
  }

  /// Set when the pointer was cancelled (the system took the gesture, the app
  /// went to the background). See [_onPanEnd] for why this can't be read off
  /// the end details.
  bool _cancelled = false;

  void _onPanStart(Offset local) {
    _moved = false;
    _cancelled = false;
    // Re-check rather than trusting that this pan was the claimed one: with no
    // scroll view competing, an ordinary drag anywhere on the dial also wins
    // the arena and lands here.
    if (!_grabAt(local)) return;
    final seg = widget.profile.boundaryNear(_geometry.minuteAt(local))!;
    setState(() => _dragging = seg.id);
  }

  void _onPanUpdate(Offset local) {
    final id = _dragging;
    if (id == null) return;
    _moved = true;
    widget.onBoundaryDragged!(id, snapMinute(_geometry.minuteAt(local)));
  }

  /// Ends the drag. Note this also runs on a *cancelled* pointer: once a drag
  /// is accepted, a cancel is delivered as an end (with no velocity), not as
  /// `onCancel` — so [_cancelled] is what tells them apart.
  void _onPanEnd(Offset local) {
    if (_dragging == null) return;
    setState(() => _dragging = null);
    if (_cancelled) return; // the system took the gesture; do nothing with it
    // Claiming the pointer at down-time costs us the tap recognizer, so a
    // press on a boundary that never moved has to select the wedge itself —
    // otherwise the blocks next to a boundary would be untappable.
    if (_moved) {
      widget.onBoundaryDragEnd?.call();
    } else {
      _select(local);
    }
  }

  /// A gesture that was cancelled before it was ever accepted.
  void _onPanCancel() {
    if (_dragging == null) return;
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = Size(constraints.maxWidth, constraints.maxHeight);
          return MouseRegion(
            cursor: _dragging != null
                ? SystemMouseCursors.grabbing
                : MouseCursor.defer,
            child: RawGestureDetector(
              gestures: {
                if (widget.onSegmentTapped != null)
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        TapGestureRecognizer.new,
                        (r) => r.onTapDown = (d) => _select(d.localPosition),
                      ),
                if (_editable)
                  _BoundaryDragRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        _BoundaryDragRecognizer
                      >(
                        () => _BoundaryDragRecognizer(
                          isGrab: _grabAt,
                          onCancelled: () => _cancelled = true,
                        ),
                        (r) {
                          r.onStart = (d) => _onPanStart(d.localPosition);
                          r.onUpdate = (d) => _onPanUpdate(d.localPosition);
                          r.onEnd = (d) => _onPanEnd(d.localPosition);
                          r.onCancel = _onPanCancel;
                        },
                      ),
              },
              child: CustomPaint(
                size: _size,
                painter: DialPainter(
                  profile: widget.profile,
                  nowMin: widget.nowMin,
                  mode: widget.mode,
                  palette: widget.palette,
                  selectedSegmentId: widget.selectedSegmentId,
                  actuals: widget.actuals,
                  overlay: widget.overlay,
                  subBlocks: widget.subBlocks,
                  showHandles: _editable,
                  draggingBoundaryId: _dragging,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A pan recognizer that claims the pointer outright when it lands on a
/// draggable boundary.
///
/// Without this, dragging a boundary inside the scrolling day view just scrolls
/// the page: the scroll view's vertical-drag recognizer reaches its slop first
/// and wins the arena. Deciding at pointer-down keeps that from being a
/// tug-of-war — a touch on a boundary is the dial's, anything else is left to
/// the arena as usual, so the page still scrolls when dragged from a wedge.
///
/// The cost is the tap recognizer for that one pointer, which
/// [_DialViewState._onPanEnd] makes up for by selecting on a claimed press that
/// never moved.
class _BoundaryDragRecognizer extends PanGestureRecognizer {
  _BoundaryDragRecognizer({required this.isGrab, required this.onCancelled});

  /// Whether a pointer landing at this position (local to the dial) is a grab.
  final bool Function(Offset localPosition) isGrab;

  /// Called when the pointer is cancelled. An *accepted* drag reports a cancel
  /// as an ordinary end, so without this the dial couldn't tell a stolen
  /// gesture from a finger lifted in place.
  final VoidCallback onCancelled;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final grab = isGrab(event.localPosition);
    super.addAllowedPointer(event);
    // `dragStartBehavior: start` means accepting here reports the drag from
    // where the finger actually landed, not from where the slop was crossed.
    if (grab) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) onCancelled();
    super.handleEvent(event);
  }
}
