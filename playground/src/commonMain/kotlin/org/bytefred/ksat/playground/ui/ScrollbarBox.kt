package org.bytefred.ksat.playground.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.BoxWithConstraintsScope
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * Wraps a scrolling area and draws a scrollbar on its right edge (Compose on Android and the web has
 * no built-in one; ported from ktoy). The thumb's length reflects the visible fraction, its position
 * the scroll offset, and it can be dragged (mouse or finger). It shows only when there is something
 * to scroll.
 */
@Composable
fun ScrollbarBox(vScroll: ScrollState, modifier: Modifier = Modifier, thumbColor: Color = THUMB_COLOR, content: @Composable () -> Unit) {
    BoxWithConstraints(modifier.testTag("scroll-area")) {
        content()
        val max = vScroll.maxValue
        if (max > 0) {
            val trackPx = constraints.maxHeight.toFloat()
            Thumb(
                trackPx = trackPx,
                visibleFraction = trackPx / (trackPx + max),
                position = vScroll.value.toFloat() / max,
                color = thumbColor,
                onDrag = { delta, travel -> if (travel > 0f) vScroll.dispatchRawDelta(delta * max / travel) },
            )
        }
    }
}

/**
 * The same for a LazyColumn (the output log can have many lines). Its total height is not known, so
 * the thumb follows the item counts: visible items / all items, and the first visible item.
 */
@Composable
fun ScrollbarBox(listState: LazyListState, modifier: Modifier = Modifier, thumbColor: Color = THUMB_COLOR, content: @Composable () -> Unit) {
    BoxWithConstraints(modifier.testTag("scroll-area")) {
        content()
        val info = listState.layoutInfo
        val total = info.totalItemsCount
        val visible = info.visibleItemsInfo
        if (total > 0 && visible.isNotEmpty() && (listState.canScrollForward || listState.canScrollBackward)) {
            val trackPx = constraints.maxHeight.toFloat()
            val itemPx = visible.sumOf { it.size }.toFloat() / visible.size
            val scrollable = total - visible.size
            Thumb(
                trackPx = trackPx,
                visibleFraction = visible.size.toFloat() / total,
                position = if (scrollable <= 0) 0f else (listState.firstVisibleItemIndex.toFloat() / scrollable).coerceIn(0f, 1f),
                color = thumbColor,
                // moving the thumb across the track scrolls through all items
                onDrag = { delta, travel -> if (travel > 0f) listState.dispatchRawDelta(delta * scrollable * itemPx / travel) },
            )
        }
    }
}

/** One draggable thumb along the right edge; [onDrag] gets the drag delta and the track's free travel (px). */
@Composable
private fun BoxWithConstraintsScope.Thumb(
    trackPx: Float,
    visibleFraction: Float,
    position: Float,
    color: Color,
    onDrag: (delta: Float, travel: Float) -> Unit,
) {
    val thumbPx = trackPx * visibleFraction.coerceIn(0.08f, 1f)
    val travel = trackPx - thumbPx
    val drag = rememberDraggableState { delta -> onDrag(delta, travel) }
    with(LocalDensity.current) {
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .offset(y = (travel * position).toDp())
                .width(THUMB_THICKNESS)
                .height(thumbPx.toDp())
                .clip(RoundedCornerShape(3.dp))
                .background(color)
                .draggable(drag, Orientation.Vertical)
                .testTag("vscroll-thumb"),
        )
    }
}

private val THUMB_THICKNESS = 6.dp
private val THUMB_COLOR = Color(0x66000000)
