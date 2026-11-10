package io.github.junrepos.serial_todo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 홈 화면 "오늘" 위젯.
 * 앱이 저장한 widget_json(오늘 ★ 항목 + 남는 자리는 바로 할 수 있는 항목)을 그린다.
 * - 행 탭 → 앱에서 그 항목 편집, 동그라미 → 백그라운드에서 완료 처리, + → 오늘 할 일 추가
 * - 마감 D-day는 여기서 오늘 날짜로 계산해 자정이 지나도 맞게 보인다.
 * - 위젯 높이에 들어가는 만큼만 행을 보여 줘 잘린 행이 생기지 않게 한다.
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    private val slots = 6
    private val labelIds = intArrayOf(R.id.label0, R.id.label1, R.id.label2, R.id.label3, R.id.label4, R.id.label5)
    private val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
    private val checkIds = intArrayOf(R.id.check0, R.id.check1, R.id.check2, R.id.check3, R.id.check4, R.id.check5)
    private val checkImgIds =
        intArrayOf(R.id.check_img0, R.id.check_img1, R.id.check_img2, R.id.check_img3, R.id.check_img4, R.id.check_img5)
    private val starIds = intArrayOf(R.id.star0, R.id.star1, R.id.star2, R.id.star3, R.id.star4, R.id.star5)
    private val titleIds = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4, R.id.title5)
    private val subIds = intArrayOf(R.id.sub0, R.id.sub1, R.id.sub2, R.id.sub3, R.id.sub4, R.id.sub5)
    private val dueIds = intArrayOf(R.id.due0, R.id.due1, R.id.due2, R.id.due3, R.id.due4, R.id.due5)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id, widgetData)
    }

    /** 크기를 바꾸면 들어가는 행 수가 달라지므로 다시 그린다. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(context: Context, manager: AppWidgetManager, widgetId: Int, prefs: SharedPreferences) {
        val views = RemoteViews(context.packageName, R.layout.today_widget)
        val open = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.header, open)
        views.setOnClickPendingIntent(
            R.id.add,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("serialtodo://add")),
        )
        views.setTextViewText(R.id.date, SimpleDateFormat("M월 d일 EEEE", Locale.KOREAN).format(Calendar.getInstance().time))

        val data = try {
            prefs.getString("widget_json", null)?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }

        if (data == null) {
            showEmpty(views, "로그인이 필요해요", "앱을 열어 로그인하세요")
            views.setOnClickPendingIntent(R.id.empty, open)
            views.setViewVisibility(R.id.count, View.GONE)
            views.setViewVisibility(R.id.progress, View.GONE)
            manager.updateAppWidget(widgetId, views)
            return
        }

        val items = data.optJSONArray("items")
        val n = items?.length() ?: 0
        val remaining = data.optInt("remaining", 0)
        val doneToday = data.optInt("doneToday", 0)

        // 남은 ★ 개수 배지
        if (remaining > 0) {
            views.setTextViewText(R.id.count, "${remaining}개 남음")
            views.setViewVisibility(R.id.count, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.count, View.GONE)
        }

        // 오늘 진행률
        val total = doneToday + remaining
        if (total > 0) {
            views.setViewVisibility(R.id.progress, View.VISIBLE)
            views.setProgressBar(R.id.progress, 100, doneToday * 100 / total, false)
        } else {
            views.setViewVisibility(R.id.progress, View.GONE)
        }

        if (n == 0) {
            if (doneToday > 0) {
                showEmpty(views, "오늘 할 일을 모두 끝냈어요", "오늘 ${doneToday}개 완료")
            } else {
                showEmpty(views, "할 일이 없어요", "+ 를 눌러 추가하세요")
            }
            views.setOnClickPendingIntent(R.id.empty, open)
            manager.updateAppWidget(widgetId, views)
            return
        }
        views.setViewVisibility(R.id.empty, View.GONE)

        // 위젯 높이에 들어가는 만큼만
        val fit = rowsThatFit(manager, widgetId, total > 0)
        var used = 0
        var budget = fit.availableDp
        var full = false
        for (i in 0 until slots) {
            views.setViewVisibility(labelIds[i], View.GONE)
            views.setViewVisibility(rowIds[i], View.GONE)
            if (i >= n || full) continue
            val it = items!!.getJSONObject(i)
            val isToday = it.optBoolean("today")
            // 첫 "바로 할 수 있음" 항목 위에 구분 라벨 (★ 항목이 없으면 맨 위)
            val needLabel = !isToday && (i == 0 || items.getJSONObject(i - 1).optBoolean("today"))
            val cost = ROW_DP + if (needLabel) LABEL_DP else 0
            if (budget < cost && used > 0) {
                full = true
                continue
            }
            budget -= cost
            used++
            if (needLabel) views.setViewVisibility(labelIds[i], View.VISIBLE)
            bindRow(context, views, i, it)
        }
        manager.updateAppWidget(widgetId, views)
    }

    private fun bindRow(context: Context, views: RemoteViews, i: Int, it: JSONObject) {
        val itemId = it.optString("id")
        val done = it.optBoolean("done")
        val title = it.optString("title")
        val parent = it.optString("parent", "")
        val due = it.optString("due", "")

        views.setViewVisibility(rowIds[i], View.VISIBLE)
        views.setViewVisibility(starIds[i], if (it.optBoolean("today") && !done) View.VISIBLE else View.GONE)

        val text = SpannableString(title)
        if (done) {
            text.setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        } else {
            text.setSpan(StyleSpan(Typeface.BOLD), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        views.setTextViewText(titleIds[i], text)
        views.setTextColor(titleIds[i], context.getColor(if (done) R.color.widget_muted else R.color.widget_text))
        views.setImageViewResource(checkImgIds[i], if (done) R.drawable.widget_ic_check_done else R.drawable.widget_ic_check)

        if (parent.isNotEmpty()) {
            views.setTextViewText(subIds[i], parent)
            views.setViewVisibility(subIds[i], View.VISIBLE)
        } else {
            views.setViewVisibility(subIds[i], View.GONE)
        }

        val d = daysUntil(due)
        if (d == null || done) {
            views.setViewVisibility(dueIds[i], View.GONE)
        } else {
            val (label, chip, color) = when {
                d < 0 -> Triple("${-d}일 지남", R.drawable.widget_chip_danger, R.color.widget_danger)
                d == 0 -> Triple("오늘 마감", R.drawable.widget_chip_danger, R.color.widget_danger)
                d <= 2 -> Triple("D-$d", R.drawable.widget_chip_warn, R.color.widget_warn)
                else -> Triple("D-$d", R.drawable.widget_chip_chip, R.color.widget_muted)
            }
            views.setTextViewText(dueIds[i], label)
            views.setInt(dueIds[i], "setBackgroundResource", chip)
            views.setTextColor(dueIds[i], context.getColor(color))
            views.setViewVisibility(dueIds[i], View.VISIBLE)
        }

        val enc = Uri.encode(itemId)
        views.setOnClickPendingIntent(
            rowIds[i],
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("serialtodo://open?id=$enc")),
        )
        if (done) {
            // 이미 체크한 행은 다시 눌러도 아무 일 없게 앱 열기로 둔다
            views.setOnClickPendingIntent(
                checkIds[i],
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("serialtodo://open?id=$enc")),
            )
        } else {
            views.setOnClickPendingIntent(
                checkIds[i],
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("serialtodo://done?id=$enc")),
            )
        }
    }

    private fun showEmpty(views: RemoteViews, title: String, sub: String) {
        views.setViewVisibility(R.id.empty, View.VISIBLE)
        views.setTextViewText(R.id.empty_title, title)
        views.setTextViewText(R.id.empty_sub, sub)
        for (i in 0 until slots) {
            views.setViewVisibility(labelIds[i], View.GONE)
            views.setViewVisibility(rowIds[i], View.GONE)
        }
    }

    private class Fit(val availableDp: Int)

    /** 머리·진행률·여백을 뺀, 행에 쓸 수 있는 높이(dp). 크기 정보를 모르면 넉넉히 잡는다. */
    private fun rowsThatFit(manager: AppWidgetManager, widgetId: Int, withProgress: Boolean): Fit {
        val opts = manager.getAppWidgetOptions(widgetId)
        // 세로 화면에서는 MAX_HEIGHT 가 실제 높이에 가깝다
        val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        if (h <= 0) return Fit(10_000)
        val chrome = 24 /* 위아래 여백 */ + 44 /* 머리 */ + if (withProgress) 14 else 0
        return Fit(h - chrome)
    }

    private fun daysUntil(due: String): Int? {
        if (due.length < 10) return null
        return try {
            val y = due.substring(0, 4).toInt()
            val m = due.substring(5, 7).toInt()
            val d = due.substring(8, 10).toInt()
            val target = Calendar.getInstance().apply {
                clear()
                set(y, m - 1, d)
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

    companion object {
        private const val ROW_DP = 52 // 타일 48 + 간격 4
        private const val LABEL_DP = 24
    }
}
