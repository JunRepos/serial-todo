package io.github.junrepos.serial_todo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/*
 * 스크롤되는 목록형 위젯 두 가지.
 *  - 계열: 목표(계열)를 누르면 그 아래 프로젝트·액션이 순서대로 펼쳐진다. 동그라미로 완료.
 *  - 일정·마감: 오늘부터의 일정과 마감인 할 일을 날짜별로. 누르면 앱에서 연다.
 * 데이터는 앱이 저장한 widget_json 의 series / agenda 를 쓴다.
 */

private const val KIND_SERIES = "series"
private const val KIND_AGENDA = "agenda"
private const val ACTION_ROW = "io.github.junrepos.serial_todo.widget.ROW"
private const val EXTRA_OP = "op"
private const val EXTRA_ID = "id"
private const val PREFS = "list_widget"
private const val KEY_OPEN = "open_goals"

private fun mutableFlags(): Int {
    var f = PendingIntent.FLAG_UPDATE_CURRENT
    if (Build.VERSION.SDK_INT >= 31) f = f or PendingIntent.FLAG_MUTABLE
    return f
}

private fun readData(prefs: SharedPreferences): JSONObject? = try {
    prefs.getString("widget_json", null)?.let { JSONObject(it) }
} catch (e: Exception) {
    null
}

private fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Calendar.getInstance().time)

/** 머리·빈 화면·목록 어댑터까지 공통으로 붙인다. */
private fun baseViews(
    context: Context,
    widgetId: Int,
    kind: String,
    title: String,
    sub: String,
    empty: String,
): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.list_widget)
    views.setTextViewText(R.id.list_title, title)
    views.setTextViewText(R.id.list_sub, sub)
    views.setTextViewText(R.id.list_empty, empty)
    views.setOnClickPendingIntent(R.id.header, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
    views.setOnClickPendingIntent(
        R.id.add,
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("serialtodo://add")),
    )
    val svc = Intent(context, ListWidgetService::class.java).apply {
        // 위젯마다 다른 어댑터가 되도록 주소로 구분한다
        data = Uri.parse("serialtodo://list/$kind/$widgetId")
    }
    views.setRemoteAdapter(R.id.list, svc)
    views.setEmptyView(R.id.list, R.id.list_empty)
    return views
}

class SeriesWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = readData(widgetData)
        val goals = data?.optJSONArray(KIND_SERIES)
        val sub = when {
            data == null -> "앱을 열어 로그인하세요"
            goals == null || goals.length() == 0 -> "진행 중인 계열이 없어요"
            else -> "진행 중 ${goals.length()}개"
        }
        for (id in appWidgetIds) {
            val views = baseViews(context, id, KIND_SERIES, "계열", sub, "하위 항목이 있는 목표가 여기 보여요")
            val row = Intent(context, SeriesWidgetProvider::class.java).apply { action = ACTION_ROW }
            views.setPendingIntentTemplate(R.id.list, PendingIntent.getBroadcast(context, 1, row, mutableFlags()))
            appWidgetManager.updateAppWidget(id, views)
        }
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ROW) {
            super.onReceive(context, intent)
            return
        }
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        when (intent.getStringExtra(EXTRA_OP)) {
            "toggle" -> {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val open = HashSet(prefs.getStringSet(KEY_OPEN, emptySet()) ?: emptySet())
                if (!open.remove(id)) open.add(id)
                prefs.edit().putStringSet(KEY_OPEN, open).apply()
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, SeriesWidgetProvider::class.java))
                manager.notifyAppWidgetViewDataChanged(ids, R.id.list)
            }
            // 완료는 오늘 위젯과 같은 길로: Dart 백그라운드 콜백이 표시를 바꾸고 큐에 넣는다
            "done" -> HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("serialtodo://done?id=${Uri.encode(id)}"),
            ).send()
        }
    }
}

class AgendaWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = readData(widgetData)
        val sub = if (data == null) {
            "앱을 열어 로그인하세요"
        } else {
            SimpleDateFormat("M월 d일 EEEE", Locale.KOREAN).format(Calendar.getInstance().time)
        }
        for (id in appWidgetIds) {
            val views = baseViews(context, id, KIND_AGENDA, "일정·마감", sub, "다가오는 일정이나 마감이 없어요")
            // 줄을 누르면 앱에서 그 항목을 연다 (줄마다 주소만 채워 넣는다)
            val open = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
            }
            views.setPendingIntentTemplate(R.id.list, PendingIntent.getActivity(context, 2, open, mutableFlags()))
            appWidgetManager.updateAppWidget(id, views)
        }
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list)
    }
}

class QuickAddWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.quick_add_widget)
            val add = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("serialtodo://add"))
            views.setOnClickPendingIntent(android.R.id.background, add)
            views.setOnClickPendingIntent(R.id.add, add)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class ListWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val kind = intent.data?.pathSegments?.firstOrNull() ?: KIND_SERIES
        return ListFactory(applicationContext, kind)
    }
}

/** 화면에 그릴 한 줄 */
private class Row(
    val type: Int,
    val id: String,
    val title: String,
    val sub: String = "",
    val count: String = "",
    val chip: String = "",
    val chipKind: Int = CHIP_PLAIN,
    val open: Boolean = false,
    val done: Boolean = false,
    val dim: Boolean = false,
    val event: Boolean = false,
    val depth: Int = 0,
)

private const val TYPE_GOAL = 0
private const val TYPE_LABEL = 1
private const val TYPE_ITEM = 2
private const val CHIP_PLAIN = 0
private const val CHIP_WARN = 1
private const val CHIP_DANGER = 2

private class ListFactory(private val context: Context, private val kind: String) :
    RemoteViewsService.RemoteViewsFactory {

    private var rows: List<Row> = emptyList()

    override fun onCreate() {}
    override fun onDestroy() {}
    override fun getCount(): Int = rows.size
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 3
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false

    override fun onDataSetChanged() {
        rows = try {
            val data = readData(HomeWidgetPlugin.getData(context))
            when {
                data == null -> emptyList()
                kind == KIND_AGENDA -> agendaRows(data.optJSONArray(KIND_AGENDA))
                else -> seriesRows(data.optJSONArray(KIND_SERIES))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun seriesRows(goals: JSONArray?): List<Row> {
        if (goals == null) return emptyList()
        val open = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY_OPEN, emptySet())
            ?: emptySet()
        val out = ArrayList<Row>()
        for (i in 0 until goals.length()) {
            val g = goals.getJSONObject(i)
            val gid = g.optString("id")
            val isOpen = open.contains(gid)
            out.add(
                Row(
                    TYPE_GOAL,
                    gid,
                    g.optString("title"),
                    count = "${g.optInt("done")}/${g.optInt("total")}",
                    chip = if (g.optBoolean("blocked")) "대기" else "",
                    open = isOpen,
                ),
            )
            if (!isOpen) continue
            val items = g.optJSONArray("rows") ?: continue
            for (j in 0 until items.length()) {
                val r = items.getJSONObject(j)
                val depth = r.optInt("depth", 1)
                if (r.optString("t") == "p") {
                    out.add(Row(TYPE_LABEL, r.optString("id"), r.optString("title"), count = r.optString("count"), depth = depth))
                    continue
                }
                val done = r.optBoolean("done")
                val blocked = r.optBoolean("blocked")
                val d = daysUntil(r.optString("due"))
                val (chip, chipKind) = when {
                    done -> Pair("", CHIP_PLAIN)
                    blocked -> Pair("대기", CHIP_WARN)
                    d == null -> Pair("", CHIP_PLAIN)
                    d < 0 -> Pair("${-d}일 지남", CHIP_DANGER)
                    d == 0 -> Pair("오늘 마감", CHIP_DANGER)
                    d <= 2 -> Pair("D-$d", CHIP_WARN)
                    else -> Pair("D-$d", CHIP_PLAIN)
                }
                out.add(
                    Row(
                        TYPE_ITEM,
                        r.optString("id"),
                        (if (r.optBoolean("today") && !done) "★ " else "") + r.optString("title"),
                        chip = chip,
                        chipKind = chipKind,
                        done = done,
                        dim = blocked && !done,
                        depth = depth,
                    ),
                )
            }
        }
        return out
    }

    private fun agendaRows(items: JSONArray?): List<Row> {
        if (items == null) return emptyList()
        val today = todayKey()
        val out = ArrayList<Row>()
        var lastDate = ""
        var overdueLabel = false
        val dayFmt = SimpleDateFormat("M월 d일 (E)", Locale.KOREAN)
        val keyFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        for (i in 0 until items.length()) {
            val it = items.getJSONObject(i)
            val date = it.optString("date")
            val event = it.optBoolean("e")
            if (date.length < 10) continue
            val past = date < today
            // 지난 일정은 버리고, 지난 마감은 맨 위에 모아 보여 준다
            if (past && event) continue
            if (past) {
                if (!overdueLabel) {
                    out.add(Row(TYPE_LABEL, "", "지난 마감"))
                    overdueLabel = true
                }
            } else if (date != lastDate) {
                lastDate = date
                val d = daysUntil(date) ?: 0
                val name = try {
                    dayFmt.format(keyFmt.parse(date)!!)
                } catch (e: Exception) {
                    date
                }
                val rel = when (d) {
                    0 -> "오늘"
                    1 -> "내일"
                    else -> "${d}일 뒤"
                }
                out.add(Row(TYPE_LABEL, "", name, count = rel))
            }
            out.add(
                Row(
                    TYPE_ITEM,
                    it.optString("id"),
                    it.optString("title"),
                    sub = it.optString("parent"),
                    chip = if (past) "${-(daysUntil(date) ?: 0)}일 지남" else "",
                    chipKind = CHIP_DANGER,
                    event = event,
                ),
            )
        }
        return out
    }

    override fun getViewAt(position: Int): RemoteViews {
        val r = rows.getOrNull(position) ?: return RemoteViews(context.packageName, R.layout.widget_row_label)
        val dp = context.resources.displayMetrics.density
        when (r.type) {
            TYPE_GOAL -> {
                val v = RemoteViews(context.packageName, R.layout.widget_row_goal)
                v.setTextViewText(R.id.row_chev, if (r.open) "▾" else "▸")
                v.setTextViewText(R.id.row_title, r.title)
                v.setTextViewText(R.id.row_count, r.count)
                v.setViewVisibility(R.id.row_chip, if (r.chip.isEmpty()) View.GONE else View.VISIBLE)
                v.setOnClickFillInIntent(R.id.row_tile, Intent().putExtra(EXTRA_OP, "toggle").putExtra(EXTRA_ID, r.id))
                return v
            }
            TYPE_LABEL -> {
                val v = RemoteViews(context.packageName, R.layout.widget_row_label)
                v.setTextViewText(R.id.row_title, r.title)
                v.setTextViewText(R.id.row_count, r.count)
                v.setViewPadding(
                    R.id.row_root,
                    ((12 + (r.depth - 1).coerceAtLeast(0) * 14) * dp).toInt(),
                    (8 * dp).toInt(),
                    (12 * dp).toInt(),
                    (2 * dp).toInt(),
                )
                return v
            }
        }
        val v = RemoteViews(context.packageName, R.layout.widget_row_item)
        v.setViewPadding(R.id.row_root, ((r.depth - 1).coerceAtLeast(0) * 14 * dp).toInt(), 0, (10 * dp).toInt(), 0)
        v.setTextViewText(R.id.row_title, r.title)
        v.setTextColor(
            R.id.row_title,
            context.getColor(if (r.done || r.dim) R.color.widget_muted else R.color.widget_text),
        )
        v.setInt(
            R.id.row_title,
            "setPaintFlags",
            if (r.done) android.graphics.Paint.STRIKE_THRU_TEXT_FLAG or android.graphics.Paint.ANTI_ALIAS_FLAG
            else android.graphics.Paint.ANTI_ALIAS_FLAG,
        )
        v.setImageViewResource(
            R.id.row_check_img,
            when {
                r.event -> R.drawable.widget_ic_event
                r.done -> R.drawable.widget_ic_check_done
                else -> R.drawable.widget_ic_check
            },
        )
        if (r.sub.isEmpty()) {
            v.setViewVisibility(R.id.row_sub, View.GONE)
        } else {
            v.setTextViewText(R.id.row_sub, r.sub)
            v.setViewVisibility(R.id.row_sub, View.VISIBLE)
        }
        if (r.chip.isEmpty()) {
            v.setViewVisibility(R.id.row_chip, View.GONE)
        } else {
            val (bg, color) = when (r.chipKind) {
                CHIP_DANGER -> Pair(R.drawable.widget_chip_danger, R.color.widget_danger)
                CHIP_WARN -> Pair(R.drawable.widget_chip_warn, R.color.widget_warn)
                else -> Pair(R.drawable.widget_chip_chip, R.color.widget_muted)
            }
            v.setTextViewText(R.id.row_chip, r.chip)
            v.setInt(R.id.row_chip, "setBackgroundResource", bg)
            v.setTextColor(R.id.row_chip, context.getColor(color))
            v.setViewVisibility(R.id.row_chip, View.VISIBLE)
        }
        if (kind == KIND_AGENDA) {
            // 줄 전체를 누르면 앱에서 그 항목 열기
            val open = Intent().setData(Uri.parse("serialtodo://open?id=${Uri.encode(r.id)}"))
            v.setOnClickFillInIntent(R.id.row_root, open)
        } else {
            // 줄 화면은 재사용되므로 끝낸 줄에도 반드시 다시 채운다(앞 줄의 '완료' 동작이 남지 않게)
            v.setOnClickFillInIntent(
                R.id.row_check,
                Intent().putExtra(EXTRA_OP, if (r.done) "noop" else "done").putExtra(EXTRA_ID, r.id),
            )
        }
        return v
    }

    private fun daysUntil(due: String): Int? {
        if (due.length < 10) return null
        return try {
            val target = Calendar.getInstance().apply {
                clear()
                set(due.substring(0, 4).toInt(), due.substring(5, 7).toInt() - 1, due.substring(8, 10).toInt())
            }
            val now = Calendar.getInstance()
            val today = Calendar.getInstance().apply {
                clear()
                set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH))
            }
            Math.round((target.timeInMillis - today.timeInMillis) / 86_400_000.0).toInt()
        } catch (e: Exception) {
            null
        }
    }
}
