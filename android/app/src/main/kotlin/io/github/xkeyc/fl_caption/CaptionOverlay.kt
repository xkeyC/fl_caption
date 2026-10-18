package io.github.xkeyc.fl_caption

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The floating caption window over other apps, laid out like the desktop
 * caption bar: [history] earlier lines (dimmed, one row each for the
 * translation and the source) above the line being spoken (two rows each).
 * Rows have a fixed height, so the window never jumps as text grows; long
 * text shows its end. A plain view (no second Flutter engine), dragged
 * vertically by the finger's screen position and kept on the screen.
 */
object CaptionOverlay {
    private class Line(val translation: TextView, val source: TextView)

    private var window: WindowManager? = null
    private var root: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var lines: List<Line> = emptyList()

    /** Earlier lines shown above the current one. */
    private var history = 1

    /** The translation's size in sp (the source is 0.75 of it). */
    private var fontSize = 19f

    /** The last texts, oldest first, to fill a rebuilt window. */
    private var texts: List<Pair<String, String>> = emptyList()

    /** The window's top, kept across rebuilds (-1: not placed yet). */
    private var lastY = -1

    /** Called when the user closes the window with its ✕. */
    var onClosed: (() -> Unit)? = null

    fun canShow(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** New layout settings; a shown window is rebuilt with them. */
    fun configure(context: Context, history: Int, fontSize: Float) {
        this.history = history.coerceIn(0, 3)
        this.fontSize = fontSize.coerceIn(12f, 32f)
        if (root != null) {
            hide()
            show(context)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    fun show(context: Context) {
        if (root != null) return
        val app = context.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        fun dp(v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, app.resources.displayMetrics)

        fun text(sp: Float, color: Int, rows: Int) = TextView(app).apply {
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
            setLines(rows)
            isVerticalScrollBarEnabled = false
            setShadowLayer(4f, 0f, 0f, 0xDD000000.toInt())
        }

        val column = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14f).toInt(), dp(8f).toInt(), dp(30f).toInt(), dp(10f).toInt())
        }
        val built = mutableListOf<Line>()
        for (i in 0..history) {
            val current = i == history
            val rows = if (current) 2 else 1
            val line = Line(
                text(fontSize, 0xFFFFFFFF.toInt(), rows),
                text(fontSize * 0.75f, 0xCCFFFFFF.toInt(), rows),
            )
            if (!current) {
                line.translation.alpha = 0.55f
                line.source.alpha = 0.55f
            }
            column.addView(line.translation)
            column.addView(line.source)
            built.add(line)
        }
        val close = TextView(app).apply {
            text = "✕"
            setTextColor(0x99FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setPadding(dp(10f).toInt(), dp(6f).toInt(), dp(10f).toInt(), dp(6f).toInt())
            setOnClickListener {
                hide()
                onClosed?.invoke()
            }
        }
        val root = FrameLayout(app).apply {
            background = GradientDrawable().apply {
                setColor(0xA6000000.toInt())
                cornerRadius = dp(12f)
            }
            addView(column, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            ))
            addView(close, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END,
            ))
        }

        val screen = app.resources.displayMetrics
        val margin = dp(8f).toInt()
        val params = WindowManager.LayoutParams(
            screen.widthPixels - margin * 2,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = margin
            y = if (lastY >= 0) lastY else (screen.heightPixels * 0.62).toInt()
        }

        // Dragged by the finger's screen position (rawY), so moving the
        // window never feeds back into the gesture.
        var downRawY = 0f
        var downY = 0
        root.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawY = event.rawY
                    downY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val max = app.resources.displayMetrics.heightPixels - view.height
                    params.y = (downY + (event.rawY - downRawY).toInt()).coerceIn(0, maxOf(0, max))
                    lastY = params.y
                    wm.updateViewLayout(view, params)
                    true
                }
                else -> false
            }
        }

        wm.addView(root, params)
        this.window = wm
        this.root = root
        this.params = params
        this.lines = built
        render()
    }

    /** The lines to show, oldest first: (source, translation). */
    fun update(texts: List<Pair<String, String>>) {
        this.texts = texts
        render()
    }

    private fun render() {
        if (lines.isEmpty()) return
        // The newest texts fill the rows from the bottom (current line last).
        val shown = texts.takeLast(lines.size)
        val offset = lines.size - shown.size
        lines.forEachIndexed { i, line ->
            val (source, translation) = shown.getOrNull(i - offset) ?: ("" to "")
            val placeholder = i == lines.lastIndex && source.isEmpty() && translation.isEmpty()
            showTail(line.translation, translation)
            showTail(line.source, if (placeholder) "FL Caption" else source)
        }
    }

    /** Captions grow at their end: show the last rows, not the first. */
    private fun showTail(view: TextView, text: String) {
        view.text = text
        view.post {
            val layout = view.layout ?: return@post
            val hidden = layout.height - (view.height - view.paddingTop - view.paddingBottom)
            view.scrollTo(0, maxOf(0, hidden))
        }
    }

    fun hide() {
        val root = root ?: return
        try {
            window?.removeView(root)
        } catch (_: Exception) {
        }
        this.root = null
        this.window = null
        this.params = null
        this.lines = emptyList()
    }
}
