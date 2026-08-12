package de.khonager.typesync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

abstract class TypeSyncNotesWidgetProvider : AppWidgetProvider() {
    protected abstract val kind: String
    protected open val layoutId = R.layout.typesync_notes_widget

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateWidgets(context, manager, ids)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, options: Bundle,
    ) = updateWidgets(context, manager, intArrayOf(id))

    protected open fun updateWidgets(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id -> manager.updateAppWidget(id, createViews(context)) }
    }

    protected fun createViews(context: Context): RemoteViews {
        val data = HomeWidgetPlugin.getData(context)
        val imageKey = if (kind == "largest") {
            "typesync_largest_${data.getString(LARGEST_METRIC_KEY, "size")}_image"
        } else {
            "typesync_${kind}_image"
        }
        val bitmap = data.getString(imageKey, null)
            ?.let(::File)
            ?.takeIf(File::exists)
            ?.let { BitmapFactory.decodeFile(it.absolutePath) }

        val views = RemoteViews(context.packageName, layoutId)
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.typesync_notes_widget_image, bitmap)
        }
        views.setOnClickPendingIntent(R.id.typesync_notes_widget_root, launchIntent(context))
        return views
    }

    private fun launchIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context, kind.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val LARGEST_METRIC_KEY = "typesync_largest_metric"
    }
}

class TypeSyncRecentlyOpenedWidgetProvider : TypeSyncNotesWidgetProvider() {
    override val kind = "recent"
}

class TypeSyncFrequentlyOpenedWidgetProvider : TypeSyncNotesWidgetProvider() {
    override val kind = "frequent"
}

class TypeSyncLargestNotesWidgetProvider : TypeSyncNotesWidgetProvider() {
    override val kind = "largest"
    override val layoutId = R.layout.typesync_largest_notes_widget

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_SET_METRIC) {
            val metric = intent.getStringExtra(EXTRA_METRIC) ?: "size"
            HomeWidgetPlugin.getData(context).edit().putString(LARGEST_METRIC_KEY, metric).apply()
            val manager = AppWidgetManager.getInstance(context)
            updateWidgets(context, manager, manager.getAppWidgetIds(
                android.content.ComponentName(context, TypeSyncLargestNotesWidgetProvider::class.java),
            ))
            return
        }
        super.onReceive(context, intent)
    }

    override fun updateWidgets(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id ->
            val views = createViews(context)
            listOf("size", "characters", "lines").forEach { metric ->
                val viewId = when (metric) {
                    "size" -> R.id.typesync_metric_size
                    "characters" -> R.id.typesync_metric_characters
                    else -> R.id.typesync_metric_lines
                }
                val intent = Intent(context, TypeSyncLargestNotesWidgetProvider::class.java).apply {
                    action = ACTION_SET_METRIC
                    putExtra(EXTRA_METRIC, metric)
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, metric.hashCode(), intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(viewId, pendingIntent)
            }
            manager.updateAppWidget(id, views)
        }
    }

    companion object {
        private const val ACTION_SET_METRIC = "de.khonager.typesync.SET_LARGEST_METRIC"
        private const val EXTRA_METRIC = "metric"
    }
}
