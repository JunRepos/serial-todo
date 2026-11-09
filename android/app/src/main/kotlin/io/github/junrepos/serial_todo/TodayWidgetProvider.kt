package io.github.junrepos.serial_todo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 홈 화면 "오늘" 위젯. 앱이 저장한 widget_json 을 그린다.
 * 행 탭 → 앱에서 해당 항목 편집, 체크 → 백그라운드 콜백으로 완료 처리.
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    private val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4)
    private val titleIds = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4)
    private val dueIds = intArrayOf(R.id.due0, R.id.due1, R.id.due2, R.id.due3, R.id.due4)
    private val checkIds = intArrayOf(R.id.check0, R.id.check1, R.id.check2, R.id.check3, R.id.check4)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("widget_json", null)
        val data = try {
            if (raw != null) JSONObject(raw) else null
        } catch (e: Exception) {
            null
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            val open = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.header, open)

            if (data == null) {
                views.setTextViewText(R.id.header_title, "오늘")
                views.setTextViewText(R.id.header_count, "")
                views.setTextViewText(R.id.empty, "앱을 열어 로그인하세요")
                views.setViewVisibility(R.id.empty, View.VISIBLE)
                rowIds.forEach { views.setViewVisibility(it, View.GONE) }
                views.setOnClickPendingIntent(R.id.empty, open)
                appWidgetManager.updateAppWidget(id, views)
                continue
            }

            val items = data.optJSONArray("items")
            val count = data.optInt("count", 0)
            views.setTextViewText(R.id.header_title, data.optString("title", "오늘"))
            views.setTextViewText(R.id.header_count, if (count > 0) "${count}개" else "")

            val n = items?.length() ?: 0
            views.setViewVisibility(R.id.empty, if (n == 0) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.empty, "할 일이 없습니다")
            views.setOnClickPendingIntent(R.id.empty, open)

            for (i in rowIds.indices) {
                if (i >= n) {
                    views.setViewVisibility(rowIds[i], View.GONE)
                    continue
                }
                val it = items!!.getJSONObject(i)
                val itemId = it.optString("id")
                val due = it.optString("due", "")
                views.setViewVisibility(rowIds[i], View.VISIBLE)
                views.setTextViewText(titleIds[i], it.optString("title"))
                views.setTextViewText(dueIds[i], due)
                views.setViewVisibility(dueIds[i], if (due.isEmpty()) View.GONE else View.VISIBLE)
                views.setTextColor(
                    dueIds[i],
                    context.getColor(if (it.optBoolean("over")) R.color.widget_danger else R.color.widget_muted),
                )
                val enc = Uri.encode(itemId)
                views.setOnClickPendingIntent(
                    rowIds[i],
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("serialtodo://open?id=$enc"),
                    ),
                )
                views.setOnClickPendingIntent(
                    checkIds[i],
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("serialtodo://done?id=$enc")),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
